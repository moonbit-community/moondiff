///|
fn viewed_test_timeout(model : Model) -> Model {
  viewed_test_saved(
    model,
    Err(
      @github_client.HttpRequestError(
        status=504,
        code="github_timeout",
        detail="Timeout",
      ),
    ),
  )
}

///|
fn viewed_test_tick(model : Model) -> Model {
  update_viewed(
    model,
    Check(model.viewed.epoch, model.viewed.serial, model.viewed.retry),
    _ => @rabbita.none,
  ).0
}

///|
test "mark and unmark keep their target through every old value and only a target read settles them" {
  for before in [@protocol.FileViewedState::Viewed, Unviewed, Dismissed] {
    let loaded = viewed_test_loaded(viewed_test_model(), before)
    let writing = viewed_test_toggle(loaded)
    let mut checking = viewed_test_timeout(writing)
    for attempt in 0..<7 {
      assert_true(checking.viewed.loading)
      let waiting = viewed_test_loaded(checking, before)
      assert_true(
        waiting.viewed.files[0].pending == checking.viewed.files[0].pending,
      )
      assert_true(
        waiting.viewed.files[0].state == writing.viewed.files[0].state,
      )
      assert_eq(viewed_test_expanded(waiting), viewed_test_expanded(writing))
      assert_true(viewed_test_toggle(waiting) == waiting)
      assert_eq(waiting.viewed.retry, Int::min(attempt + 1, 6))
      assert_eq(waiting.viewed.poll_scheduled, attempt < 6)
      checking = if attempt < 6 { viewed_test_tick(waiting) } else { waiting }
    }
    assert_true(viewed_test_tick(checking) == checking)
    let manual = update_viewed(checking, Refresh, _ => @rabbita.none).0
    assert_eq(manual.viewed.retry, 0)
    assert_true(manual.viewed.loading)
    assert_true(update_viewed(manual, Refresh, _ => @rabbita.none).0 == manual)
    let confirmed = viewed_test_loaded(
      manual,
      writing.viewed.files[0].state.unwrap(),
    )
    assert_true(confirmed.viewed.files[0].pending is None)
    assert_false(confirmed.viewed.poll_scheduled)
  }
}

///|
test "confirmation failures retry but rate limits identity and stale snapshots pause polling" {
  let checking = viewed_test_timeout(
    viewed_test_toggle(viewed_test_loaded(viewed_test_model(), Unviewed)),
  )
  for
    (status, code, automatic) in [
      (503, "unavailable", true),
      (0, "network_error", true),
      (429, "rate_limit", false),
      (401, "authentication_required", false),
      (409, "pull_snapshot_changed", false),
    ] {
    let failed = update_viewed(
        checking,
        Loaded(
          checking.viewed.epoch,
          checking.viewed.serial,
          Err(@github_client.HttpRequestError(status~, code~, detail="failure")),
        ),
        _ => @rabbita.none,
      ).0
    assert_eq(failed.viewed.poll_scheduled, automatic)
    assert_true(failed.viewed.files[0].pending is Some(_))
    assert_true(failed.viewed.error is Some(_))
  }
}

///|
test "timers and storage responses cannot act across new rounds accounts or pages" {
  let waiting = viewed_test_loaded(
    viewed_test_timeout(
      viewed_test_toggle(viewed_test_loaded(viewed_test_model(), Unviewed)),
    ),
    Unviewed,
  )
  let tick = Check(
    waiting.viewed.epoch,
    waiting.viewed.serial,
    waiting.viewed.retry,
  )
  let manual = update_viewed(waiting, Refresh, _ => @rabbita.none).0
  assert_true(update_viewed(manual, tick, _ => @rabbita.none).0 == manual)
  let restored = viewed_interaction_update(waiting, Auth(RestoreAuth))
  assert_true(update_viewed(restored, tick, _ => @rabbita.none).0 == restored)
  let writing = update_viewed(
      viewed_test_loaded(viewed_test_model(), Unviewed),
      Toggle(waiting.generation, 0),
      _ => @rabbita.none,
    ).0
  let record = writing.viewed.files[0].pending.unwrap().record
  let changed = {
    ..writing,
    viewed: { ..writing.viewed, epoch: writing.viewed.epoch + 1, },
  }
  assert_true(
    update_viewed(changed, Stored(writing.viewed.epoch, 0, record, true), _ => {
      @rabbita.none
    }).0 ==
    changed,
  )
}

///|
test "storage failure prevents writing and rolls back without changing the draft" {
  let loaded = viewed_test_loaded(viewed_test_model(), Unviewed)
  let draft = viewed_interaction_update(
    loaded,
    Review(OpenInlineDraft(0, viewed_interaction_anchor())),
  )
  let draft = viewed_interaction_update(draft, Review(DraftBodyChanged("keep")))
  let storing = update_viewed(draft, Toggle(draft.generation, 0), _ => {
      @rabbita.none
    }).0
  let pending = storing.viewed.files[0].pending.unwrap()
  assert_false(pending.stored)
  let ignored = viewed_test_saved(
    storing,
    Err(
      @github_client.HttpRequestError(
        status=504,
        code="timeout",
        detail="timeout",
      ),
    ),
  )
  assert_true(ignored == storing)
  let failed = update_viewed(
      storing,
      Stored(storing.viewed.epoch, 0, pending.record, false),
      _ => @rabbita.none,
    ).0
  assert_true(failed.viewed.files[0].pending is None)
  assert_true(failed.viewed.files[0].state == Some(Unviewed))
  assert_true(failed.viewed.files[0].error is Some(_))
  assert_eq(viewed_test_expanded(failed), viewed_test_expanded(draft))
  assert_true(failed.review.draft() == draft.review.draft())
}

///|
test "restored records use user repository PR and verbatim paths independent of index and snapshot" {
  let original = viewed_test_toggle(
    viewed_test_loaded(viewed_test_model(), Unviewed),
  )
  let record = original.viewed.files[0].pending.unwrap().record
  let initial = viewed_interaction_model()
  guard initial.phase is Showing(view) && view.pull_snapshot is Some(snapshot) else {
    fail("missing view")
  }
  let files = [view.files[1], { ..view.files[0], expanded: true, }]
  let changed = {
    ..initial,
    auth: original.auth,
    phase: Showing({
      ..view,
      files,
      pull_snapshot: Some({
        ..snapshot,
        head: { ..snapshot.head, sha: "b".repeat(40), },
      }),
    }),
  }
  let restored = restore_viewed_records(changed, [
    { ..record, owner: record.owner.to_upper(), repo: record.repo.to_upper(), },
  ])
  assert_true(restored.viewed.files[0].pending is None)
  assert_true(
    restored.viewed.files[1].pending
    is Some({ confirming: true, stored: true, .. }),
  )
  assert_true(restored.phase == changed.phase)
  for
    unrelated in [
      { ..record, user_id: "another-user", },
      { ..record, owner: "another-owner", },
      { ..record, repo: "another-repo", },
      { ..record, number: "999", },
      { ..record, path: "src/old.mbt", },
      { ..record, path: record.path + "\n", },
    ] {
    assert_true(
      restore_viewed_records(changed, [unrelated]).viewed.files.all(f => {
        f.pending is None
      }),
    )
  }
  assert_true(record.key() != { ..record, path: record.path + "\n", }.key())
}

///|
test "confirmation reads never overlap while another file remains writable" {
  let initial = viewed_interaction_loaded(viewed_interaction_model())
  let first = viewed_test_toggle(initial)
  let checking = viewed_test_timeout(first)
  let other = viewed_interaction_update(
    checking,
    Viewed(Toggle(checking.generation, 1)),
  )
  assert_true(other.viewed.files[1].pending is Some({ stored: true, .. }))
  assert_true(other.viewed.loading)
  assert_eq(other.viewed.read_serial, checking.viewed.read_serial)
  let old = update_viewed(
      other,
      Loaded(
        checking.viewed.epoch,
        checking.viewed.serial,
        Ok(viewed_test_data(Viewed)),
      ),
      _ => @rabbita.none,
    ).0
  assert_false(old.viewed.loading)
  assert_true(old.viewed.refresh_needed)
  assert_true(old.viewed.files[0].pending is Some(_))
}

///|
test "Viewed waits for a stable user ID before restoring storage" {
  let initial = viewed_test_model()
  let missing = {
    ..initial,
    auth: SignedIn(user_id=None, login=Some("alice"), install_url=None),
  }
  assert_true(viewed_scope(missing) is None)
  assert_true(begin_viewed_refresh(missing, _ => @rabbita.none).0 == missing)
}

///|
test "authentication interruption before persistence completes cannot leave an unsent write pending" {
  let loaded = viewed_test_loaded(viewed_test_model(), Unviewed)
  let storing = update_viewed(loaded, Toggle(loaded.generation, 0), _ => {
      @rabbita.none
    }).0
  let pending = storing.viewed.files[0].pending.unwrap()
  let checking = viewed_interaction_update(storing, Auth(RestoreAuth))
  assert_true(checking.viewed.files[0].pending is None)
  assert_true(checking.viewed.files[0].state == Some(Unviewed))
  let late = update_viewed(
      checking,
      Stored(storing.viewed.epoch, 0, pending.record, true),
      _ => @rabbita.none,
    ).0
  assert_true(late == checking)
}
