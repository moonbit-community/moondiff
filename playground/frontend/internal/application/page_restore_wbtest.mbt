///|
fn restoration_model() -> Model {
  auth_identity_test_model(
    SignedIn(login=Some("alice"), user_id=Some("alice"), install_url=None),
    Some("alice"),
  )
}

///|
fn restoration_status(
  model : Model,
  status : Result[ApiAuthStatus, Error],
) -> Model {
  update_auth(
    model,
    ReactivationAuthStatusLoaded(
      model.auth_revision,
      model.generation,
      model.route,
      status,
    ),
    Emit(_ => @rabbita.none),
  ).0
}

///|
test "page restoration keeps loaded content collapse choices and current account drafts" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let base = restoration_model()
  guard base.phase is Showing(view) else { fail("showing") }
  for
    side in [
      @change.Loading,
      Ready(["loaded"]),
      NotRequested,
      LoadFailed("failed"),
      CannotRender("binary", false),
    ] {
    let file = {
      ..view.files[0],
      expanded: false,
      old_side: side,
      new_side: @change.Loading,
      collapsed_sections: ["section"],
    }
    let before = with_phase(base, Showing(set_file_state(view, 0, file)))
    let hidden = update_auth(before, RestoreAuth, emit).0
    assert_true(hidden.restore_pending)
    assert_true(hidden.review.draft() == before.review.draft())
    let restored = restoration_status(hidden, Ok(signed_in_api_status("alice")))
    assert_false(restored.restore_pending)
    assert_eq(restored.generation, before.generation)
    assert_true(restored.phase == before.phase)
    assert_true(restored.file_tree == before.file_tree)
    assert_true(restored.review.draft() == before.review.draft())
    let focused = restoration_status(
      restored,
      Ok(signed_in_api_status("alice")),
    )
    assert_false(focused.restore_pending)
    assert_true(focused.phase == before.phase)
  }
}

///|
test "failed restoration retains its marker until a later status or login succeeds" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let before = restoration_model()
  let hidden = update_auth(before, RestoreAuth, emit).0
  let failed = restoration_status(hidden, Err(authentication_required_error()))
  assert_true(failed.auth is AuthFailed(_))
  assert_true(failed.restore_pending)
  assert_true(failed.review.draft() == before.review.draft())
  let again = restoration_status(failed, Err(authentication_required_error()))
  assert_true(again.restore_pending)
  let status = signed_in_api_status("alice")
  let focused = restoration_status(again, Ok(status))
  assert_false(focused.restore_pending)
  let loaded = update_auth(
      again,
      AuthStatusLoaded(again.auth_revision, Ok(status)),
      emit,
    ).0
  assert_false(loaded.restore_pending)
  let pending = restoration_status(again, Ok(pending_api_status("attempt")))
  assert_true(pending.restore_pending)
  let signed_in = update_auth(
      pending,
      DeviceUpdated(
        pending.auth_revision,
        "attempt",
        false,
        Ok({
          request_id: "attempt",
          status: {
            ..status,
            device_flow: pending_api_status("attempt").device_flow.map(flow => {
              ..flow,
              phase: @protocol.DevicePhase::Completed,
            }),
          },
        }),
      ),
      emit,
    ).0
  assert_false(signed_in.restore_pending)
  assert_true(signed_in.review.draft() == before.review.draft())
}

///|
test "restoration restarts unfinished metadata once and preserves existing failures" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let before = restoration_model()
  let reference = before.route.unwrap()
  let pull = review_test_pull()
  let compare : ApiCompare = { merge_base_commit: { sha: "base", }, }
  for
    phase in [
      Idle,
      LoadingCommit(
        reference~,
        repository=reference_repository(reference),
        page=2,
        first=None,
        files=[],
      ),
      LoadingPullMetadata(reference~, attempt=0),
      LoadingPullCommitMetadata(reference~),
      LoadingPullSnapshot(
        reference~,
        attempt=0,
        metadata=pull,
        compare=None,
        page=1,
        files=[],
      ),
      ValidatingPullSnapshot(reference~, attempt=0, metadata=pull, compare~, files=[]),
    ] {
    let loading = { ..before, phase, }
    let hidden = update_auth(loading, RestoreAuth, emit).0
    let restored = restoration_status(hidden, Ok(signed_in_api_status("alice")))
    assert_eq(restored.generation, before.generation + 1)
    assert_false(restored.restore_pending)
    assert_true(restored.phase is LoadingPullMetadata(..))
    assert_true(restored.review.draft() == before.review.draft())
    let focused = restoration_status(
      restored,
      Ok(signed_in_api_status("alice")),
    )
    assert_eq(focused.generation, restored.generation)
    assert_true(focused.phase == restored.phase)
  }
  let failed = { ..before, phase: LoadFailed("existing failure"), }
  let restored = restoration_status(
    update_auth(failed, RestoreAuth, emit).0,
    Ok(signed_in_api_status("alice")),
  )
  assert_true(restored.phase == failed.phase)
  assert_eq(restored.generation, failed.generation)
  let startup = { ..initial_model(), route: Some(reference), }
  let restored = update_auth(startup, RestoreAuth, emit).0
  let ready = update_auth(
      restored,
      AuthStatusLoaded(restored.auth_revision, Ok(anonymous_api_status())),
      emit,
    ).0
  assert_eq(ready.generation, 1)
  assert_false(ready.restore_pending)
}

///|
test "navigation and account boundaries clear restoration and reject old responses" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let before = restoration_model()
  let hidden = update_auth(before, RestoreAuth, emit).0
  let response = ReactivationAuthStatusLoaded(
    hidden.auth_revision,
    hidden.generation,
    hidden.route,
    Ok(signed_in_api_status("alice")),
  )
  for path in ["/", "/upstream/project/pull/18"] {
    let url = @url.parse("http://localhost" + path)
    let navigated = update_ui(hidden, RouteChanged(url), emit).0
    assert_false(navigated.restore_pending)
    assert_true(update_auth(navigated, response, emit).0 == navigated)
  }
  let switched = restoration_status(hidden, Ok(signed_in_api_status("bob")))
  assert_false(switched.restore_pending)
  assert_eq(switched.generation, hidden.generation + 1)
  assert_true(switched.review.draft() is None)
  assert_true(
    update_load(
      switched,
      SourceLoaded(hidden.generation, 0, New, Ok(("text/plain", b"stale"))),
      emit,
    ).0 ==
    switched,
  )
}

///|
test "device start failures back off without replacing the attempt or auth revision" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let initial = with_auth(
    initial_model(),
    Authorizing(starting_device("attempt"), ""),
  )
  let error = @github_client.HttpRequestError(
    status=0,
    code="network_error",
    detail="offline",
  )
  for delay in [10, 20, 40, 60, 60]; model = initial {
    let next = update_auth(
        model,
        DeviceUpdated(0, "attempt", true, Err(error)),
        emit,
      ).0
    guard next.auth is Authorizing(flow, _) else { fail("retrying") }
    assert_eq(flow.id, "attempt")
    assert_true(flow.phase is @protocol.Starting)
    assert_eq(flow.retry_after, delay)
    assert_eq(next.auth_revision, initial.auth_revision)
    continue next
  }
}
