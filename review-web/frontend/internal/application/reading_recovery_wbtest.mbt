///|
test "recovery registers queued comments before dispatch and retains metadata list validation" {
  let before = new_reading_recovery(review_test_model(Anonymous(None)))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let token = before.reading_recovery.unwrap()
  let signed = update(
      before,
      Auth(
        ReactivationAuthStatusLoaded(
          before.auth_revision,
          before.generation,
          before.route,
          Ok(signed_in_api_status("alice")),
        ),
      ),
      emit,
    ).model
  assert_eq(token.comments_queued, 1)
  assert_true(token.pending())
  assert_true(token.comments_refresh is None)
  let begun = update(
      signed,
      Review(BeginCommentsRefresh(signed.generation, signed.route.unwrap())),
      emit,
    ).model
  assert_eq(token.comments_queued, 0)
  assert_eq(token.comments_refresh, Some(begun.review.refresh_id))
  let id = begun.review.refresh_id
  let listed = update(
      begun,
      Review(
        Domain(
          CommentsMetadataLoaded(begun.generation, id, Ok(review_test_pull())),
        ),
      ),
      emit,
    ).model
  assert_eq(token.comments_refresh, Some(id))
  let validated = update(
      listed,
      Review(
        Domain(
          CommentsLoaded(
            listed.generation,
            id,
            Ok({ issue_comments: [], review_comments: [], commit_comments: [], }),
          ),
        ),
      ),
      emit,
    ).model
  assert_eq(token.comments_refresh, Some(id))
  ignore(
    update(
      validated,
      Review(
        Domain(
          CommentsValidated(validated.generation, id, Ok(review_test_pull())),
        ),
      ),
      emit,
    ),
  )
  assert_true(token.comments_refresh is None)
}

///|
test "Viewed storage continues into the remote read while stale epochs cannot end recovery" {
  let before = new_reading_recovery(
    review_test_model(
      SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
    ),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = begin_viewed_refresh(before, emit).0
  let token = loading.reading_recovery.unwrap()
  assert_eq(token.viewed, Some((loading.viewed.epoch, loading.viewed.serial)))
  let restored = update(
      loading,
      Viewed(Restored(loading.viewed.epoch, loading.viewed.serial, Ok([]))),
      emit,
    ).model
  assert_true(restored.viewed.storage_ready)
  assert_true(restored.viewed.loading)
  assert_eq(token.viewed, Some((restored.viewed.epoch, restored.viewed.serial)))
  let stale = update(
      restored,
      Viewed(
        Loaded(
          restored.viewed.epoch - 1,
          restored.viewed.serial,
          Ok(viewed_test_data(Unviewed)),
        ),
      ),
      emit,
    ).model
  assert_true(token.viewed is Some(_))
  ignore(
    update(
      stale,
      Viewed(
        Loaded(
          stale.viewed.epoch,
          stale.viewed.serial,
          Ok(viewed_test_data(Unviewed)),
        ),
      ),
      emit,
    ),
  )
  assert_true(token.viewed is None)
  assert_false(token.pending())
}

///|
test "first Pending CI result ends recovery work and later polling cannot rejoin" {
  let model = new_reading_recovery(merge_test_model())
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let started = begin_pull_merge_refresh(model, emit).0
  let token = started.reading_recovery.unwrap()
  assert_true(token.merge is Some(_))
  let pending = update(
      started,
      PullMerge(
        StatusLoaded(
          started.pull_merge.epoch,
          started.pull_merge.serial,
          Ok(merge_test_status(state=Pending)),
        ),
      ),
      emit,
    ).model
  assert_false(token.pending())
  assert_true(pending.pull_merge.poll_scheduled)
  let polling = update(
      pending,
      PullMerge(
        Poll(
          pending.pull_merge.epoch,
          pending.pull_merge.serial,
          pending.pull_merge.retry,
        ),
      ),
      emit,
    ).model
  assert_true(polling.pull_merge.loading)
  assert_false(token.pending())
}

///|
test "auth reactivation work merges and old revisions cannot finish newer work" {
  let model = new_reading_recovery(merge_test_model())
  let token = model.reading_recovery.unwrap()
  let messages : Array[Msg] = []
  let emit : @rabbita.Emit[Msg] = msg => {
    messages.push(msg)
    @rabbita.none
  }
  let first = recovery_auth_request(Some(token), model.auth_revision, emit)
  let second = recovery_auth_request(Some(token), model.auth_revision, emit)
  assert_eq(token.auth_requests.length(), 2)
  ignore(first())
  ignore(prepare_reading_recovery(model, messages[0]))
  ignore(prepare_reading_recovery(model, messages[0]))
  assert_eq(token.auth_requests.length(), 1)
  let third = recovery_auth_request(Some(token), model.auth_revision + 1, emit)
  let next = reconcile_reading_recovery(
    model,
    { ..model, auth_revision: model.auth_revision + 1, },
    Auth(RestoreAuth),
  )
  assert_eq(token.auth_requests.length(), 1)
  ignore(second())
  ignore(prepare_reading_recovery(next, messages[1]))
  assert_eq(token.auth_requests.length(), 1)
  ignore(third())
  ignore(prepare_reading_recovery(next, messages[2]))
  assert_false(token.pending())
}

///|
test "business results cannot retire registered requests and old rounds cannot finish new work" {
  let model = new_reading_recovery(merge_test_model())
  let token = model.reading_recovery.unwrap()
  let emit : @rabbita.Emit[Msg] = _ => @rabbita.none
  ignore(recovery_auth_request(Some(token), model.auth_revision, emit))
  ignore(
    prepare_reading_recovery(
      model,
      Auth(
        ReactivationAuthStatusLoaded(
          model.auth_revision,
          model.generation - 1,
          model.route,
          Ok(signed_in_api_status("alice")),
        ),
      ),
    ),
  )
  assert_eq(token.auth_requests.length(), 1)
  let authorizing = {
    ..model,
    auth: auth_status_from_api(pending_api_status("current")),
  }
  ignore(recovery_auth_request(Some(token), model.auth_revision, emit))
  ignore(
    prepare_reading_recovery(
      authorizing,
      Auth(
        DeviceUpdated(
          model.auth_revision,
          "replaced",
          false,
          Err(@github_client.GitHubRequestError("old response")),
        ),
      ),
    ),
  )
  assert_eq(token.auth_requests.length(), 2)
  let next = new_reading_recovery(model)
  let current = next.reading_recovery.unwrap()
  ignore(recovery_auth_request(Some(current), model.auth_revision, emit))
  ignore(
    prepare_reading_recovery(
      next,
      Ui(ReadingAuthRequestFinished(token.id, model.auth_revision, 1)),
    ),
  )
  ignore(
    prepare_reading_recovery(
      next,
      Ui(ReadingAuthRequestFinished(current.id, model.auth_revision + 1, 1)),
    ),
  )
  assert_eq(current.auth_requests.length(), 1)
}

///|
test "device completion retains a follow-up request registered by its business result" {
  let model = new_reading_recovery(
    review_test_model(auth_status_from_api(pending_api_status("current"))),
  )
  let token = model.reading_recovery.unwrap()
  let emit : @rabbita.Emit[Msg] = _ => @rabbita.none
  ignore(recovery_auth_request(Some(token), model.auth_revision, emit))
  let next = update(
      model,
      Auth(
        DeviceUpdated(
          model.auth_revision,
          "current",
          false,
          Ok({ request_id: "current", status: pending_api_status("current"), }),
        ),
      ),
      emit,
    ).model
  assert_eq(token.auth_requests.length(), 2)
  ignore(
    prepare_reading_recovery(
      next,
      Ui(ReadingAuthRequestFinished(token.id, model.auth_revision, 1)),
    ),
  )
  assert_eq(token.auth_requests.length(), 1)
  assert_true(token.pending())
}

///|
test "a new auth recovery can start before completed metadata cleanup arrives" {
  let model = new_reading_recovery(merge_test_model())
  let token = model.reading_recovery.unwrap()
  token.finished = true
  ignore(
    recovery_auth_request(Some(token), model.auth_revision, _ => @rabbita.none),
  )
  assert_false(token.pending())
  let next = prepare_reading_recovery(model, Auth(RestoreAuth))
  assert_true(next.reading_recovery.unwrap().id > token.id)
  let cleaned = update(next, Ui(ReadingRecoveryFinished(token.id)), _ => {
      @rabbita.none
    }).model
  assert_eq(
    cleaned.reading_recovery.unwrap().id,
    next.reading_recovery.unwrap().id,
  )
}

///|
test "skipped capture can recover a new pause before cleanup while cancellation stays blocked" {
  for cancelled in [false, true] {
    let model = new_reading_recovery(merge_test_model())
    let token = model.reading_recovery.unwrap()
    token.finished = true
    token.cancelled = cancelled
    let activated = prepare_reading_recovery(model, Review(PageReactivated))
    assert_eq(activated.reading_recovery.unwrap().id != token.id, !cancelled)
    let paused = reconcile_reading_recovery(
      model,
      { ..model, source_pause: Some(AnonymousRequests), },
      Review(PageReactivated),
    )
    assert_eq(paused.reading_recovery.unwrap().id != token.id, !cancelled)
  }
}

///|
test "manual comment refresh owns its refresh ID through metadata and supersession" {
  let model = review_test_model(Anonymous(None))
  let emit : @rabbita.Emit[Msg] = _ => @rabbita.none
  let started = update(
      { ..model, reading_recovery_blocked: true, },
      Review(RefreshComments),
      emit,
    ).model
  let token = started.reading_recovery.unwrap()
  assert_false(started.reading_recovery_blocked)
  assert_eq(token.comments_refresh, Some(started.review.refresh_id))
  let next = update(
      started,
      Review(BeginCommentsRefresh(started.generation, started.route.unwrap())),
      emit,
    ).model
  assert_true(next.review.refresh_id > started.review.refresh_id)
  assert_true(token.comments_refresh is None)
}

///|
test "cancelled rounds cannot restart from late auth or source responses and old cleanup cannot clear a new round" {
  let model = new_reading_recovery(merge_test_model())
  let token = model.reading_recovery.unwrap()
  token.cancelled = true
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let cleaned = update(model, Ui(ReadingRecoveryFinished(token.id)), emit).model
  assert_true(cleaned.reading_recovery is None)
  assert_true(cleaned.reading_recovery_blocked)
  let other_page = reconcile_reading_recovery(
    cleaned,
    { ..cleaned, generation: cleaned.generation + 1, },
    Review(PageReactivated),
  )
  assert_false(other_page.reading_recovery_blocked)
  let late = update(cleaned, Review(PageReactivated), emit).model
  assert_true(late.reading_recovery is None)
  let retry = prepare_reading_recovery(late, Auth(RestoreAuth))
  assert_true(retry.reading_recovery is Some(_))
  assert_true(retry.reading_recovery.unwrap().id > token.id)
  let still = update(retry, Ui(ReadingRecoveryFinished(token.id)), emit).model
  assert_true(still.reading_recovery is Some(_))
  let changed = reconcile_reading_recovery(
    still,
    { ..still, generation: still.generation + 1, },
    Review(PageReactivated),
  )
  assert_true(changed.reading_recovery is None)
  assert_true(still.reading_recovery.unwrap().cancelled)
}
