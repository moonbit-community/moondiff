///|
fn finish_preparing_fixture(model : Model) -> Model {
  let mut next = model
  if model.access.preparing is Some(prepared) {
    for index, file in prepared.view.files {
      for
        (side, state) in [
          (SourceSide::Old, file.old_side),
          (New, file.new_side),
        ] {
        if state is Loading {
          next = home_step(
            next,
            Load(
              ReplacementSourceLoaded(
                model.generation,
                prepared.snapshot.signature,
                index,
                side,
                Ok(("text/plain", b"pub fn answer() { 42 }\n")),
              ),
            ),
          )
        }
      }
    }
  }
  next
}

///|
fn changed_snapshot_fixture(model : Model) -> @github_client.PullSnapshot {
  let snapshot = shown_snapshot(model)
  {
    ..snapshot,
    metadata: {
      ..snapshot.metadata,
      head: { ..snapshot.metadata.head, sha: "d".repeat(40), },
    },
    signature: "new-version",
  }
}

///|
test "ready page restoration reuses parsed sources diff and highlights before metadata returns" {
  let model = navigation_review_model()
  guard model.phase is Showing(view) else { fail("view") }
  let view = ensure_expanded_file_documents(
    view,
    model.diff_algorithm,
    ignore_comments=model.ignore_comments,
    ignore_tests=model.ignore_tests,
  )
  let model = with_phase(model, Showing(view))
  let home = home_step(
    save_route_memory(model),
    Ui(RouteChanged(@url.parse("http://localhost/"))),
  )
  let restored = home_step(
    home,
    Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/17"))),
  )
  guard restored.phase is Showing(ready) else {
    fail("ready before validation")
  }
  assert_true(
    @identity.same(ready.files[0].diff_cache, view.files[0].diff_cache),
  )
  assert_true(restored.access.freshness is Checking)
  assert_false(writes_allowed(restored))
  let verified = home_step(
    restored,
    Load(
      SharedSnapshotLoaded(
        restored.generation,
        Ok({ snapshot: shown_snapshot(model), confirmed: true, }),
      ),
    ),
  )
  guard verified.phase is Showing(ready) else { fail("verified") }
  assert_true(
    @identity.same(ready.files[0].diff_cache, view.files[0].diff_cache),
  )
  assert_true(writes_allowed(verified))
}

///|
test "ready page cache limits non-current pages and falls back above four MiB of source" {
  let original = navigation_review_model()
  let mut saved = original
  for number in ["18", "19", "20"] {
    saved = save_route_memory(saved)
    guard saved.phase is Showing(view) else { fail("view") }
    let reference = @github.pull_reference("upstream", "project", number)
    saved = with_phase(
      { ..saved, route: Some(reference), },
      Showing({ ..view, reference, }),
    )
  }
  let destination = @github.pull_reference("upstream", "project", "19")
  let restored = begin_change_load(saved, destination, _ => @rabbita.none).0
  assert_eq(restored.navigation.pages.length(), 2)
  assert_true(restored.phase is Showing(_))
  assert_true(ready_page(restored, original.route.unwrap()) is None)
  guard original.phase is Showing(view) else { fail("view") }
  let huge = {
    ..view,
    files: [
      { ..view.files[0], old_side: Ready(["x".repeat(4 * 1048576 + 1)]), },
    ],
  }
  let saved = save_route_memory(with_phase(original, Showing(huge)))
  assert_true(saved.navigation.pages.is_empty())
  assert_true(
    saved.navigation.routes.contains(route_key(original.route.unwrap())),
  )
  let other_user = {
    ..saved,
    navigation: original.navigation,
    last_authenticated_user_id: Some("other"),
  }
  assert_true(ready_page(other_user, original.route.unwrap()) is None)
}

///|
test "version replacement keeps old content until first source is ready and then switches once" {
  let model = navigation_review_model()
  let snapshot = changed_snapshot_fixture(model)
  let loading = home_step(
    model,
    Load(
      SharedSnapshotLoaded(model.generation, Ok({ snapshot, confirmed: true, })),
    ),
  )
  assert_true(loading.phase == model.phase)
  assert_eq(loading.generation, model.generation)
  assert_true(loading.access.preparing is Some(_))
  assert_false(writes_allowed(loading))
  let ready = finish_preparing_fixture(loading)
  assert_eq(ready.generation, model.generation + 1)
  assert_true(writes_allowed(ready))
  guard ready.phase is Showing(view) else { fail("view") }
  assert_eq(view.sha, snapshot.metadata.head.sha)
  assert_true(view.files[0].old_side is Ready(_))
  assert_true(view.files[0].new_side is Ready(_))
  assert_true(view.files[0].diff_cache.highlights is Some(_))
}

///|
test "a draft merge or identity check appearing during preparation retains the original version" {
  for blocking in 0..<3 {
    let model = navigation_review_model()
    let loading = home_step(
      model,
      Load(
        SharedSnapshotLoaded(
          model.generation,
          Ok({ snapshot: changed_snapshot_fixture(model), confirmed: true, }),
        ),
      ),
    )
    let guarded = match blocking {
      0 =>
        home_step(
          home_step(loading, Review(OpenOverallDraft)),
          Review(DraftBodyChanged("Keep original version")),
        )
      1 =>
        { ..loading, pull_merge: { ..loading.pull_merge, submitting: true, }, }
      _ =>
        { ..loading, access: { ..loading.access, identity_checking: true, }, }
    }
    let held = finish_preparing_fixture(guarded)
    assert_true(held.phase == model.phase)
    assert_eq(held.generation, model.generation)
    assert_true(held.review.draft() == guarded.review.draft())
    assert_true(held.access.freshness is Unavailable(_))
    assert_false(writes_allowed(held))
  }
}

///|
test "failed preparation and late source replies preserve a readable version and retry" {
  let model = navigation_review_model()
  let loading = home_step(
    model,
    Load(
      SharedSnapshotLoaded(
        model.generation,
        Ok({ snapshot: changed_snapshot_fixture(model), confirmed: true, }),
      ),
    ),
  )
  let failed = home_step(
    loading,
    Load(
      ReplacementSourceLoaded(
        model.generation,
        "new-version",
        0,
        Old,
        Err(GitHubRequestError::GitHubRequestError("Network unavailable")),
      ),
    ),
  )
  assert_true(failed.phase == model.phase)
  assert_true(failed.access.freshness is Unavailable(_))
  assert_false(writes_allowed(failed))
  let retried = home_step(failed, Ui(RetryRoute))
  assert_true(retried.access.freshness is Checking)
  assert_true(retried.access.preparing is None)
  let navigated = home_step(
    loading,
    Ui(RouteChanged(@url.parse("http://localhost/"))),
  )
  let late = home_step(
    navigated,
    Load(
      ReplacementSourceLoaded(
        model.generation,
        "new-version",
        0,
        New,
        Ok(("text/plain", b"pub fn other() { 0 }")),
      ),
    ),
  )
  assert_true(late.phase == navigated.phase)
}

///|
test "evicted parsed pages restore a draft's lightweight original version before adopting updates" {
  let initial = navigation_review_model()
  let editing = home_step(
    home_step(initial, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("Original version")),
  )
  let saved = save_route_memory(editing)
  let saved = {
    ..saved,
    navigation: { ..saved.navigation, pages: [], },
    phase: Idle,
    route: None,
  }
  let restored = begin_change_load(saved, initial.route.unwrap(), _ => {
      @rabbita.none
    }).0
  let restored = restore_route_memory(restored).0
  guard restored.phase is Showing(view) else { fail("lightweight original") }
  assert_eq(view.sha, shown_snapshot(initial).metadata.head.sha)
  assert_true(view.files[0].old_side is Loading)
  assert_true(view.files[0].diff_cache.highlights is None)
  assert_eq(restored.review.draft().unwrap().body, "Original version")
  let checked = home_step(
    restored,
    Load(
      SharedSnapshotLoaded(
        restored.generation,
        Ok({ snapshot: changed_snapshot_fixture(initial), confirmed: true, }),
      ),
    ),
  )
  assert_true(checked.phase == restored.phase)
  assert_true(checked.access.freshness is Unavailable(_))
  assert_true(
    checked.review.draft().unwrap().snapshot ==
    editing.review.draft().unwrap().snapshot,
  )
}

///|
test "active Viewed writes block replacement while completed stale confirmations allow Load latest" {
  let writing = viewed_test_toggle(
    viewed_test_loaded(viewed_test_model(), @protocol.FileViewedState::Unviewed),
  )
  assert_true(snapshot_replacement_blocked(writing))
  let confirming = {
    ..writing,
    viewed: {
      ..writing.viewed,
      files: writing.viewed.files.map(file => {
        ..file,
        pending: file.pending.map(pending => { ..pending, confirming: true, }),
      }),
    },
  }
  assert_true(snapshot_replacement_blocked(confirming))
  let stale = { ..confirming, viewed: { ..confirming.viewed, stale: true, }, }
  assert_false(snapshot_replacement_blocked(stale))
  let staged = home_step(
    stale,
    Load(
      SharedSnapshotLoaded(
        stale.generation,
        Ok({ snapshot: changed_snapshot_fixture(stale), confirmed: true, }),
      ),
    ),
  )
  let updated = finish_preparing_fixture(staged)
  assert_eq(updated.generation, stale.generation + 1)
  assert_true(updated.access.freshness is Confirmed)
}

///|
test "manual Load latest retains the shown page and cannot interrupt an active Viewed write" {
  let writing = mark_snapshot_stale(
    viewed_test_toggle(
      viewed_test_loaded(
        viewed_test_model(),
        @protocol.FileViewedState::Unviewed,
      ),
    ),
  )
  let checking = home_step(writing, Review(LoadLatestSnapshot))
  assert_eq(checking.generation, writing.generation)
  assert_true(checking.phase == writing.phase)
  assert_true(checking.access.reload_requested)
  let guarded = home_step(
    checking,
    Load(
      SharedSnapshotLoaded(
        checking.generation,
        Ok({ snapshot: changed_snapshot_fixture(writing), confirmed: true, }),
      ),
    ),
  )
  assert_eq(guarded.generation, writing.generation)
  assert_true(guarded.phase == writing.phase)
  assert_true(
    guarded.viewed.files[0].pending == writing.viewed.files[0].pending,
  )
  assert_true(guarded.access.freshness is Unavailable(_))
}

///|
test "manual same-version recovery clears stale permissions without recomputing file caches" {
  let original = navigation_review_model()
  let stale = mark_snapshot_stale(original)
  let checking = home_step(stale, Review(LoadLatestSnapshot))
  assert_true(checking.phase == original.phase)
  let confirmed = home_step(
    checking,
    Load(
      SharedSnapshotLoaded(
        checking.generation,
        Ok({ snapshot: shown_snapshot(original), confirmed: true, }),
      ),
    ),
  )
  assert_false(confirmed.review.snapshot_stale)
  assert_true(writes_allowed(confirmed))
  guard original.phase is Showing(before) && confirmed.phase is Showing(after) else {
    fail("shown")
  }
  assert_true(
    @identity.same(before.files[0].diff_cache, after.files[0].diff_cache),
  )
}

///|
test "a deterministic source size limit can show the new version with a render notice" {
  let model = navigation_review_model()
  let staged = home_step(
    model,
    Load(
      SharedSnapshotLoaded(
        model.generation,
        Ok({ snapshot: changed_snapshot_fixture(model), confirmed: true, }),
      ),
    ),
  )
  let limited = home_step(
    staged,
    Load(
      ReplacementSourceLoaded(
        model.generation,
        "new-version",
        0,
        New,
        Err(
          @github_client.HttpRequestError(
            status=413,
            code="source_too_large",
            detail="Cannot render: one side is larger than 1 MiB.",
          ),
        ),
      ),
    ),
  )
  assert_true(limited.access.preparing is Some(_))
  let ready = finish_preparing_fixture(limited)
  assert_eq(ready.generation, model.generation + 1)
  assert_true(ready.access.freshness is Confirmed)
  guard ready.phase is Showing(view) else { fail("new version") }
  assert_true(view.files[0].new_side is CannotRender(_, false))
}

///|
test "the parsed-page source budget includes separators and permits exactly four MiB" {
  guard navigation_review_model().phase is Showing(view) else { fail("view") }
  let exact = {
    ..view,
    files: [
      {
        ..view.files[0],
        old_side: Ready(["x".repeat(4 * 1048576)]),
        new_side: Ready([]),
      },
    ],
  }
  assert_true(retain_page(exact))
  let over = {
    ..exact,
    files: [{ ..exact.files[0], new_side: Ready(["x"]), }],
  }
  assert_false(retain_page(over))
}
