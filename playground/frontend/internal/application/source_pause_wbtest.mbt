///|
test "rate limiting settles every admitted side without leaving loading placeholders" {
  for anonymous in [true, false] {
    let model = source_prefetch_model()
    let model = pump_source_fixture(
      if anonymous {
        { ..model, auth: Anonymous(None), }
      } else {
        model
      },
    )
    let reason : @github_client.RateLimitReason = if anonymous {
      AnonymousRequests
    } else {
      AuthenticatedRequests
    }
    let pending = model.pull_sources.unwrap().pending
    let mut next = model
    for entry in pending {
      next = finish_source_fixture(
        next,
        entry,
        result=Err(@github_client.RateLimited(reason)),
      )
    }
    assert_true(next.source_pause == Some(reason))
    assert_true(next.pull_sources.unwrap().pending.is_empty())
    guard next.phase is Showing(view) else { fail("view") }
    for file in view.files[:20] {
      assert_true(file.old_side is Paused && file.new_side is Paused)
    }
    let shown = home_step(next, Home(VisibilityChanged(true)))
    let scrolled = home_step(shown, Load(AutoExpandFile(1, "src/file30.mbt")))
    assert_true(scrolled.pull_sources.unwrap().pending.is_empty())
    assert_false(auto_expand_allowed(scrolled))
    let unchanged = update_load(
        next,
        SourceLoaded(0, 0, Old, Ok(("text/plain", b"stale"))),
        _ => @rabbita.none,
      ).0
    assert_true(unchanged == next)
  }
}

///|
test "in-flight success survives a pause and a late anonymous failure resumes after sign-in" {
  let model = pump_source_fixture({
    ..source_prefetch_model(),
    auth: Anonymous(None),
  })
  let paused = finish_source_fixture(
    model,
    (0, Old),
    result=Err(@github_client.RateLimited(AnonymousRequests)),
  )
  let completed = finish_source_fixture(paused, (0, New))
  let signed_in = with_auth(
    completed,
    SignedIn(login=Some("reviewer"), user_id=Some("1"), install_url=None),
  )
  let resumed = pump_source_fixture(
    resume_source_loading(signed_in, _ => @rabbita.none).0,
  )
  let late = finish_source_fixture(
    resumed,
    (1, Old),
    result=Err(@github_client.RateLimited(AnonymousRequests)),
  )
  assert_true(late.source_pause is None)
  assert_true(late.pull_sources.unwrap().pending.length() <= 4)
  assert_false(late.pull_sources.unwrap().pending.contains((0, New)))
  guard late.phase is Showing(view) else { fail("view") }
  assert_true(view.files[0].new_side is Ready(_))
  assert_false(view.files[30].expanded)
}

///|
fn paused_review_fixture() -> Model {
  let model = review_test_model(Anonymous(None))
  guard model.phase is Showing(view) else { abort("view") }
  pause_source_loading(
    with_phase(
      { ..model, pull_sources: Some(PullSourceState::new(model.generation)), },
      Showing(
        set_file_state(view, 0, {
          ..view.files[0],
          old_side: Ready(["fn answer() { 1 }"]),
          new_side: Loading,
        }),
      ),
    ),
    AnonymousRequests,
  )
}

///|
test "starting cancelled and failed sign-in retain the anonymous pause" {
  let model = paused_review_fixture()
  for
    status in [anonymous_api_status(), pending_api_status("attempt-0000000000")] {
    let next = finish_sign_in(model, status, _ => @rabbita.none).0
    assert_true(next.source_pause == Some(AnonymousRequests))
    guard next.phase is Showing(view) else { fail("view") }
    assert_true(view.files[0].new_side is Paused)
  }
  let failed = home_step(
    model,
    Auth(
      AuthStatusLoaded(
        model.auth_revision,
        Err(@github_client.GitHubRequestError("Sign-in failed")),
      ),
    ),
  )
  assert_true(failed.source_pause == Some(AnonymousRequests))
  assert_true(failed.pull_sources.unwrap().pending.is_empty())
}

///|
test "PR login waits for confirmed snapshot and retains sources folding and draft" {
  let model = with_auth(
    paused_review_fixture(),
    SignedIn(login=Some("reviewer"), user_id=Some("reviewer"), install_url=None),
  )
  let model = home_step(
    home_step(model, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("keep draft")),
  )
  assert_true(model.review.draft() is Some({ body: "keep draft", .. }))
  let model = with_auth(
    with_auth(model, AuthFailed("expired")),
    Anonymous(None),
  )
  let model = home_step(model, Load(ToggleFile(model.generation, 0)))
  let signed_in = finish_sign_in(model, signed_in_api_status("reviewer"), _ => {
      @rabbita.none
    }).0
  assert_true(signed_in.source_pause == Some(AnonymousRequests))
  assert_true(signed_in.access.freshness is Checking)
  let failed = receive_shared_snapshot(
      signed_in,
      model.generation,
      Err(@github_client.GitHubRequestError("offline")),
      _ => @rabbita.none,
    ).0
  assert_true(failed.source_pause == Some(AnonymousRequests))
  let unconfirmed = receive_shared_snapshot(
      signed_in,
      model.generation,
      Ok({ snapshot: shown_snapshot(model), confirmed: false, }),
      _ => @rabbita.none,
    ).0
  assert_true(unconfirmed.source_pause == Some(AnonymousRequests))
  let confirmed = receive_shared_snapshot(
      signed_in,
      model.generation,
      Ok({ snapshot: shown_snapshot(model), confirmed: true, }),
      _ => @rabbita.none,
    ).0
  assert_true(confirmed.source_pause is None)
  assert_eq(confirmed.generation, model.generation)
  assert_true(confirmed.review.draft() == signed_in.review.draft())
  guard confirmed.phase is Showing(view) && model.phase is Showing(before) else {
    fail("view")
  }
  assert_false(view.files[0].expanded)
  assert_true(view.files[0].old_side == before.files[0].old_side)
  assert_true(view.files[0].new_side is Loading)
  let pending = pump_source_fixture(confirmed).pull_sources.unwrap().pending
  assert_true(pending.contains((0, New)))
  assert_false(pending.contains((0, Old)))
}

///|
test "login uses safe replacement for a changed PR and retains a blocking draft" {
  let model = paused_review_fixture()
  let signed_in = finish_sign_in(model, signed_in_api_status("reviewer"), _ => {
      @rabbita.none
    }).0
  let snapshot = changed_snapshot_fixture(model)
  let preparing = receive_shared_snapshot(
      signed_in,
      model.generation,
      Ok({ snapshot, confirmed: true, }),
      _ => @rabbita.none,
    ).0
  assert_true(preparing.source_pause == Some(AnonymousRequests))
  assert_true(preparing.phase == model.phase)
  assert_true(preparing.access.preparing is Some(_))
  let installed = finish_preparing_fixture(preparing)
  assert_true(installed.source_pause is None)
  assert_eq(installed.generation, model.generation + 1)
  let draft = home_step(
    home_step(signed_in, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("keep version")),
  )
  let blocked = receive_shared_snapshot(
      draft,
      model.generation,
      Ok({ snapshot, confirmed: true, }),
      _ => @rabbita.none,
    ).0
  assert_true(blocked.source_pause == Some(AnonymousRequests))
  assert_true(blocked.access.preparing is None)
  assert_true(blocked.review.draft() == draft.review.draft())
}

///|
test "a paused PR restored from history recreates source admission after login" {
  let model = paused_review_fixture()
  let restored = begin_change_load(
      save_route_memory(model),
      model.route.unwrap(),
      _ => @rabbita.none,
    ).0
  assert_true(restored.pull_sources is None)
  assert_true(restored.source_pause == Some(AnonymousRequests))
  let signed_in = finish_sign_in(restored, signed_in_api_status("reviewer"), _ => {
      @rabbita.none
    }).0
  let confirmed = receive_shared_snapshot(
      signed_in,
      restored.generation,
      Ok({ snapshot: shown_snapshot(model), confirmed: true, }),
      _ => @rabbita.none,
    ).0
  let resumed = pump_source_fixture(confirmed)
  assert_true(resumed.source_pause is None)
  assert_true(resumed.pull_sources.unwrap().pending.contains((0, New)))
  assert_true(resumed.pull_sources.unwrap().pending.length() <= 4)
}
