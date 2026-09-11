///|
fn viewed_test_model() -> Model {
  let model = review_test_model(
    SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
  )
  viewed_test_storage(begin_viewed_refresh(model, _ => @rabbita.none).0)
}

///|
fn viewed_test_data(
  state : @protocol.FileViewedState,
) -> @protocol.ApiPullViewed {
  let pull = review_test_pull()
  {
    base_sha: pull.base.sha,
    head_sha: pull.head.sha,
    files: [{ path: "src/main.mbt", state, }],
  }
}

///|
fn viewed_test_loaded(
  model : Model,
  state : @protocol.FileViewedState,
) -> Model {
  let model = viewed_test_storage(model)
  update_viewed(
    model,
    Loaded(model.viewed.epoch, model.viewed.serial, Ok(viewed_test_data(state))),
    _ => @rabbita.none,
  ).0
}

///|
fn viewed_test_expanded(model : Model) -> Bool {
  guard model.phase is Showing(view) else { return false }
  view.files[0].expanded
}

///|
fn viewed_test_toggle(model : Model) -> Model {
  viewed_test_stored(
    update_viewed(model, Toggle(model.generation, 0), _ => @rabbita.none).0,
    0,
  )
}

///|
fn viewed_test_saved(
  model : Model,
  result : Result[@protocol.ApiFileViewedResult, Error],
) -> Model {
  guard model.viewed.files[0].pending is Some(pending) else { return model }
  update_viewed(
    model,
    Saved(model.viewed.epoch, 0, pending.record.id, result),
    _ => @rabbita.none,
  ).0
}

///|
test "Viewed restores tri-state independently from expansion and cache" {
  let initial = viewed_test_model()
  assert_false(initial.viewed.ready)
  assert_true(initial.viewed.loading)
  let loaded = viewed_test_loaded(initial, Viewed)
  assert_false(viewed_test_expanded(loaded))
  let opened = update(loaded, Load(OpenFile(loaded.generation, 0)), _ => {
      @rabbita.none
    }).0
  assert_true(viewed_test_expanded(opened))
  assert_true(opened.viewed.files[0].state == Some(Viewed))
  let refresh = begin_viewed_refresh(opened, _ => @rabbita.none).0
  let refreshed = viewed_test_loaded(refresh, Viewed)
  assert_true(viewed_test_expanded(refreshed))
  let dismissed = viewed_test_loaded(initial, Dismissed)
  assert_true(dismissed.viewed.files[0].state == Some(Dismissed))
  assert_true(viewed_test_expanded(dismissed))
  let touched = update(initial, Load(OpenFile(initial.generation, 0)), _ => {
      @rabbita.none
    }).0
  assert_true(viewed_test_expanded(viewed_test_loaded(touched, Viewed)))
}

///|
test "Viewed optimistic updates disable duplicate writes and roll back failure with draft intact" {
  let loaded = viewed_test_loaded(viewed_test_model(), Unviewed)
  let draft = update_review(loaded, OpenOverallDraft, _ => @rabbita.none).0
  let draft = update_review(draft, DraftBodyChanged("keep this draft"), _ => {
      @rabbita.none
    }).0
  let marked = viewed_test_toggle(draft)
  assert_false(viewed_test_expanded(marked))
  assert_true(marked.viewed.files[0].state == Some(Viewed))
  assert_true(viewed_test_toggle(marked) == marked)
  let failed = viewed_test_saved(
    marked,
    Err(
      @github_client.HttpRequestError(
        status=403,
        code="permission_denied",
        detail="Denied",
      ),
    ),
  )
  assert_true(viewed_test_expanded(failed))
  assert_true(failed.viewed.files[0].state == Some(Unviewed))
  assert_true(failed.viewed.files[0].pending is None)
  assert_true(failed.viewed.files[0].error is Some(_))
  assert_true(failed.review.draft() == draft.review.draft())
  guard failed.phase is Showing(view) && draft.phase is Showing(old) else {
    fail("missing diff")
  }
  assert_true(view.files[0].diff_cache == old.files[0].diff_cache)
}

///|
test "unmark expands and failure preserves subsequent manual expansion choices" {
  let loaded = viewed_test_loaded(viewed_test_model(), Viewed)
  let unmarked = viewed_test_toggle(loaded)
  assert_true(viewed_test_expanded(unmarked))
  let manually_collapsed = update(
      unmarked,
      Load(ToggleFile(unmarked.generation, 0)),
      _ => @rabbita.none,
    ).0
  let manually_opened = update(
      manually_collapsed,
      Load(OpenFile(unmarked.generation, 0)),
      _ => @rabbita.none,
    ).0
  let failed = viewed_test_saved(
    manually_opened,
    Err(
      @github_client.HttpRequestError(
        status=403,
        code="permission_denied",
        detail="Denied",
      ),
    ),
  )
  assert_true(viewed_test_expanded(failed))
  assert_true(failed.viewed.files[0].state == Some(Viewed))
}

///|
test "reads predating writes cannot overwrite optimistic or saved states" {
  let loaded = viewed_test_loaded(viewed_test_model(), Unviewed)
  let reading = begin_viewed_refresh(loaded, _ => @rabbita.none).0
  let marked = viewed_test_toggle(reading)
  let stale_read = Loaded(
    reading.viewed.epoch,
    reading.viewed.serial,
    Ok(viewed_test_data(Unviewed)),
  )
  let ignored = update_viewed(marked, stale_read, _ => @rabbita.none).0
  assert_true(ignored.viewed.files == marked.viewed.files)
  assert_false(ignored.viewed.loading)
  let data = viewed_test_data(Viewed)
  let saved = viewed_test_saved(
    marked,
    Ok({
      base_sha: data.base_sha,
      head_sha: data.head_sha,
      file: data.files[0],
    }),
  )
  assert_true(saved.viewed.loading)
  let saved = update_viewed(saved, stale_read, _ => @rabbita.none).0
  assert_true(saved.viewed.loading)
  assert_true(saved.viewed.serial > saved.viewed.read_serial - 1)
  assert_true(
    viewed_test_loaded(saved, Viewed).viewed.files[0].state == Some(Viewed),
  )
}

///|
test "uncertain writes only settle at the target and failed confirmation retains pending state" {
  let marked = viewed_test_toggle(
    viewed_test_loaded(viewed_test_model(), Unviewed),
  )
  let uncertain = viewed_test_saved(
    marked,
    Err(
      @github_client.HttpRequestError(
        status=504,
        code="github_timeout",
        detail="Timeout",
      ),
    ),
  )
  assert_true(
    uncertain.viewed.files[0].pending is Some({ confirming: true, .. }),
  )
  assert_true(uncertain.viewed.loading)
  assert_true(viewed_test_toggle(uncertain) == uncertain)
  let confirmed = viewed_test_loaded(uncertain, Viewed)
  assert_true(confirmed.viewed.files[0].pending is None)
  assert_false(viewed_test_expanded(confirmed))
  let failed = update_viewed(
      uncertain,
      Loaded(
        uncertain.viewed.epoch,
        uncertain.viewed.serial,
        Err(
          @github_client.HttpRequestError(
            status=500,
            code="internal_error",
            detail="Unavailable",
          ),
        ),
      ),
      _ => @rabbita.none,
    ).0
  assert_true(failed.viewed.files[0].pending is Some(_))
  assert_true(failed.viewed.error is Some(_))
  let retry = begin_viewed_refresh(failed, _ => @rabbita.none).0
  let not_applied = viewed_test_loaded(retry, Unviewed)
  assert_false(viewed_test_expanded(not_applied))
  assert_true(not_applied.viewed.files[0].pending is Some(_))
  assert_true(not_applied.viewed.files[0].state == Some(Viewed))
}

///|
test "Viewed isolates account and page generations and marks changed snapshots stale" {
  let initial = viewed_test_model()
  let loaded = viewed_test_loaded(initial, Unviewed)
  let switched = {
    ..loaded,
    auth: SignedIn(login=Some("bob"), user_id=Some("2"), install_url=None),
  }
  let switched = reconcile_viewed(loaded, switched, Viewed(Refresh), _ => {
      @rabbita.none
    }).0
  assert_true(switched.viewed.epoch > loaded.viewed.epoch)
  let response = Loaded(
    initial.viewed.epoch,
    initial.viewed.serial,
    Ok(viewed_test_data(Viewed)),
  )
  assert_true(
    update_viewed(switched, response, _ => @rabbita.none).0 == switched,
  )
  let navigated = { ..loaded, generation: loaded.generation + 1, }
  let navigated = reconcile_viewed(loaded, navigated, Viewed(Refresh), _ => {
      @rabbita.none
    }).0
  assert_true(
    update_viewed(navigated, response, _ => @rabbita.none).0 == navigated,
  )
  let changed = {
    ..viewed_test_data(Viewed),
    head_sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  }
  let stale = update_viewed(
      initial,
      Loaded(initial.viewed.epoch, initial.viewed.serial, Ok(changed)),
      _ => @rabbita.none,
    ).0
  assert_true(stale.viewed.stale)
  assert_true(stale.review.snapshot_stale)
  assert_true(viewed_test_toggle(stale) == stale)
  assert_true(begin_viewed_refresh(stale, _ => @rabbita.none).0 == stale)
}

///|
test "read failure does not affect diff and non-PR or anonymous pages never load Viewed" {
  let initial = viewed_test_model()
  let broken = { ..viewed_test_data(Viewed), files: [], }
  let failed = update_viewed(
      initial,
      Loaded(initial.viewed.epoch, initial.viewed.serial, Ok(broken)),
      _ => @rabbita.none,
    ).0
  assert_true(failed.phase == initial.phase)
  assert_false(failed.viewed.ready)
  assert_true(failed.viewed.error is Some(_))
  let anonymous = { ..initial, auth: Anonymous(None), }
  assert_true(
    begin_viewed_refresh(anonymous, _ => @rabbita.none).0 == anonymous,
  )
  for target in [ChangeTarget::Commit("123abcd"), PullCommit("17", "123abcd")] {
    let model = { ..initial, phase: Showing(review_test_view(target~)), }
    assert_true(begin_viewed_refresh(model, _ => @rabbita.none).0 == model)
  }
}

///|
test "page restoration rechecks Viewed without collapsing manually opened files" {
  let loaded = viewed_test_loaded(viewed_test_model(), Viewed)
  let opened = update(loaded, Load(OpenFile(loaded.generation, 0)), _ => {
      @rabbita.none
    }).0
  let checking = {
    ..opened,
    auth: AuthChecking,
    auth_revision: opened.auth_revision + 1,
  }
  let checking = reconcile_viewed(opened, checking, Auth(RestoreAuth), _ => {
      @rabbita.none
    }).0
  let signed_in = { ..checking, auth: opened.auth, }
  let restored = reconcile_viewed(checking, signed_in, Viewed(Refresh), _ => {
      @rabbita.none
    }).0
  let refreshed = viewed_test_loaded(restored, Viewed)
  assert_true(viewed_test_expanded(refreshed))
  assert_true(refreshed.viewed.files[0].state == Some(Viewed))
}

///|
test "refresh waits for writes to different files and rejects late writes from an old account" {
  let initial = viewed_test_model()
  guard initial.phase is Showing(view) else { fail("missing view") }
  let files = view.files.copy()
  files.push({
    ..files[0],
    file: { ..files[0].file, filename: "src/second.mbt", },
  })
  let initial = begin_viewed_refresh(
      {
        ..initial,
        viewed: { ..initial.viewed, loading: false, },
        phase: Showing({ ..view, files, }),
      },
      _ => @rabbita.none,
    ).0
  let data = viewed_test_data(Unviewed)
  let data = {
    ..data,
    files: [data.files[0], { path: "src/second.mbt", state: Unviewed, }],
  }
  let loaded = update_viewed(
      initial,
      Loaded(initial.viewed.epoch, initial.viewed.serial, Ok(data)),
      _ => @rabbita.none,
    ).0
  let first = viewed_test_toggle(loaded)
  let both = update_viewed(first, Toggle(first.generation, 1), _ => {
      @rabbita.none
    }).0
  let both = viewed_test_stored(both, 1)
  let refresh = begin_viewed_refresh(both, _ => @rabbita.none).0
  assert_false(refresh.viewed.loading)
  assert_true(refresh.viewed.refresh_needed)
  let saved_first = viewed_test_saved(
    refresh,
    Ok({
      base_sha: data.base_sha,
      head_sha: data.head_sha,
      file: { path: "src/main.mbt", state: Viewed, },
    }),
  )
  assert_false(saved_first.viewed.loading)
  assert_true(saved_first.viewed.refresh_needed)
  guard both.viewed.files[1].pending is Some(pending) else {
    fail("missing write")
  }
  let saved_message = Saved(
    both.viewed.epoch,
    1,
    pending.record.id,
    Ok({
      base_sha: data.base_sha,
      head_sha: data.head_sha,
      file: { path: "src/second.mbt", state: Viewed, },
    }),
  )
  let saved_both = update_viewed(saved_first, saved_message, _ => @rabbita.none).0
  assert_true(saved_both.viewed.loading)
  assert_false(viewed_writing(saved_both.viewed))
  let changed_account = {
    ..both,
    auth: SignedIn(login=Some("bob"), user_id=Some("2"), install_url=None),
  }
  let changed_account = reconcile_viewed(
      both,
      changed_account,
      Viewed(Refresh),
      _ => @rabbita.none,
    ).0
  assert_true(
    update_viewed(changed_account, saved_message, _ => @rabbita.none).0 ==
    changed_account,
  )
}

///|
fn viewed_test_storage(model : Model) -> Model {
  if model.viewed.storage_ready || !model.viewed.loading {
    return model
  }
  update_viewed(
    model,
    Restored(model.viewed.epoch, model.viewed.serial, Ok([])),
    _ => @rabbita.none,
  ).0
}

///|
fn viewed_test_stored(model : Model, index : Int) -> Model {
  guard model.viewed.files.get(index) is Some({ pending: Some(pending), .. }) else {
    return model
  }
  update_viewed(
    model,
    Stored(model.viewed.epoch, index, pending.record, true),
    _ => @rabbita.none,
  ).0
}
