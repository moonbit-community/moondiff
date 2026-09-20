///|
fn merge_test_model(
  auth? : AuthStatus = SignedIn(
    login=Some("alice"),
    user_id=Some("1"),
    install_url=None,
  ),
) -> Model {
  let view = review_test_view()
  {
    ..initial_model(),
    generation: 5,
    route: Some(view.reference),
    phase: Showing(view),
    auth,
  }
}

///|
fn merge_test_status(
  state? : @protocol.ApiCiState = Success,
) -> @protocol.ApiPullMergeStatus {
  {
    base_sha: "1111111111111111111111111111111111111111",
    head_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    open: true,
    draft: false,
    merged: false,
    mergeable: Some(true),
    rebaseable: Some(true),
    mergeable_state: "clean",
    ci_summary: Some(state),
    ci_checks: [],
    ci_warnings: [],
  }
}

///|
test "pull merge refresh ignores stale responses and detects snapshot drift" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let initial = merge_test_model()
  let (loading, _) = begin_pull_merge_refresh(initial, emit)
  assert_true(loading.pull_merge.loading)
  assert_eq(loading.pull_merge.serial, 1)
  let (ignored, _) = update_pull_merge(
    loading,
    StatusLoaded(loading.pull_merge.epoch, 0, Ok(merge_test_status())),
    emit,
  )
  assert_true(ignored == loading)
  let changed = {
    ..merge_test_status(),
    head_sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  }
  let (stale, _) = update_pull_merge(
    loading,
    StatusLoaded(
      loading.pull_merge.epoch,
      loading.pull_merge.serial,
      Ok(changed),
    ),
    emit,
  )
  assert_true(stale.pull_merge.stale)
  assert_false(stale.pull_merge.loading)
  assert_true(stale.review.snapshot_stale)
}

///|
test "pull merge polling uses six bounded retries" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (started, _) = begin_pull_merge_refresh(merge_test_model(), emit)
  let mut model = started
  for expected_retry in 1..<=6 {
    let (scheduled, _) = update_pull_merge(
      model,
      StatusLoaded(
        model.pull_merge.epoch,
        model.pull_merge.serial,
        Ok(merge_test_status(state=Pending)),
      ),
      emit,
    )
    assert_eq(scheduled.pull_merge.retry, expected_retry)
    assert_true(scheduled.pull_merge.poll_scheduled)
    let (next, _) = update_pull_merge(
      scheduled,
      Poll(
        scheduled.pull_merge.epoch,
        scheduled.pull_merge.serial,
        scheduled.pull_merge.retry,
      ),
      emit,
    )
    assert_true(next.pull_merge.loading)
    model = next
  }
  let (finished, _) = update_pull_merge(
    model,
    StatusLoaded(
      model.pull_merge.epoch,
      model.pull_merge.serial,
      Ok(merge_test_status(state=Pending)),
    ),
    emit,
  )
  assert_eq(finished.pull_merge.retry, 6)
  assert_false(finished.pull_merge.poll_scheduled)
  assert_false(finished.pull_merge.loading)
}

///|
test "rebase merge requires authentication and submits only once" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let ready = {
    ..merge_test_model(auth=Anonymous(None)),
    pull_merge: { ..PullMergeState::new(), status: Some(merge_test_status()), },
  }
  let (anonymous, _) = update_pull_merge(ready, Submit, emit)
  assert_true(anonymous == ready)
  let signed_in = {
    ..ready,
    auth: SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
  }
  let (submitting, _) = update_pull_merge(signed_in, Submit, emit)
  assert_true(submitting.pull_merge.submitting)
  assert_eq(submitting.pull_merge.serial, 1)
  let (duplicate, _) = update_pull_merge(submitting, Submit, emit)
  assert_true(duplicate == submitting)
  let (merged, _) = update_pull_merge(
    submitting,
    MergeFinished(
      submitting.pull_merge.epoch,
      submitting.pull_merge.serial,
      Ok({
        merged: true,
        sha: Some("cccccccccccccccccccccccccccccccccccccccc"),
        message: "Pull request successfully merged",
      }),
    ),
    emit,
  )
  guard merged.pull_merge.status is Some(status) else {
    fail("expected merge status")
  }
  assert_true(status.merged)
  assert_false(status.open)
  assert_false(merged.pull_merge.submitting)
}

///|
test "merge failures become stable actionable states" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let signed_in = {
    ..merge_test_model(
      auth=SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
    ),
    pull_merge: {
      ..PullMergeState::new(),
      status: Some(merge_test_status()),
      submitting: true,
      serial: 3,
    },
  }
  let (failed, _) = update_pull_merge(
    signed_in,
    MergeFinished(
      0,
      3,
      Err(
        @github_client.HttpRequestError::HttpRequestError(
          status=409,
          code="merge_conflict",
          detail="Conflict",
        ),
      ),
    ),
    emit,
  )
  guard failed.pull_merge.status is Some(status) else {
    fail("expected merge status")
  }
  assert_true(status.mergeable is Some(false))
  assert_true(status.rebaseable is Some(false))
  assert_true(
    failed.pull_merge.error is Some(message) && message.contains("conflicts"),
  )
}

///|
test "snapshot changes during merge become stale without inventing conflicts" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let submitting = {
    ..merge_test_model(
      auth=SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
    ),
    pull_merge: {
      ..PullMergeState::new(),
      status: Some(merge_test_status()),
      submitting: true,
      serial: 4,
    },
  }
  let (stale, _) = update_pull_merge(
    submitting,
    MergeFinished(
      0,
      4,
      Err(
        @github_client.HttpRequestError::HttpRequestError(
          status=409,
          code="pull_snapshot_changed",
          detail="Snapshot changed",
        ),
      ),
    ),
    emit,
  )
  assert_false(stale.pull_merge.submitting)
  assert_true(stale.pull_merge.stale)
  assert_true(stale.review.snapshot_stale)
  guard stale.pull_merge.status is Some(status) else {
    fail("expected merge status")
  }
  assert_true(status.mergeable is Some(true))
  assert_true(status.rebaseable is Some(true))
}

///|
test "merge rejection stays retryable while expired authentication signs out" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let submitting = {
    ..merge_test_model(
      auth=SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
    ),
    pull_merge: {
      ..PullMergeState::new(),
      status: Some(merge_test_status()),
      submitting: true,
      serial: 4,
    },
  }
  let (rejected, _) = update_pull_merge(
    submitting,
    MergeFinished(
      0,
      4,
      Err(
        @github_client.HttpRequestError::HttpRequestError(
          status=422,
          code="merge_rejected",
          detail="Rejected",
        ),
      ),
    ),
    emit,
  )
  guard rejected.pull_merge.status is Some(status) else {
    fail("expected merge status")
  }
  assert_eq(status.mergeable_state, "clean")
  assert_true(pull_merge_actionable(status))
  let retrying = {
    ..rejected,
    pull_merge: { ..rejected.pull_merge, submitting: true, },
  }
  let (expired, _) = update_pull_merge(
    retrying,
    MergeFinished(
      0,
      4,
      Err(
        @github_client.HttpRequestError::HttpRequestError(
          status=401,
          code="authentication_required",
          detail="Expired",
        ),
      ),
    ),
    emit,
  )
  assert_true(expired.auth is AuthFailed(_))
  assert_false(expired.review.can_comment)
}
