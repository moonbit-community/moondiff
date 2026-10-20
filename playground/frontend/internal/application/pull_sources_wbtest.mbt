///|
fn source_prefetch_model(count~ : Int32 = 40) -> Model {
  let reference = pull_reference("upstream", "project", "17")
  let view = @change.finish_change(
    reference,
    Some({ repository: reference_repository(reference), sha: "b".repeat(40), }),
    { repository: reference_repository(reference), sha: "a".repeat(40), },
    "prefetch",
    "",
    { additions: count, deletions: count, total: count * 2, },
    Array::makei(count, index => {
      fixture_file("src/file\{index}.mbt", "modified")
    }),
  )
  {
    ..initial_model(),
    generation: 1,
    route: Some(reference),
    phase: Showing(view),
    auth: SignedIn(login=Some("reviewer"), user_id=Some("1"), install_url=None),
    pull_sources: Some(PullSourceState::new(1)),
  }
}

///|
fn pump_source_fixture(model : Model) -> Model {
  reconcile_pull_sources(model, _ => @rabbita.none).0
}

///|
fn finish_source_fixture(
  model : Model,
  entry : (Int32, SourceSide),
  result~ : Result[(String, Bytes), Error] = Ok(
    ("text/plain", b"fn answer() -> Int { 42 }\n"),
  ),
) -> Model {
  let (index, side) = entry
  pump_source_fixture(
    update_load(model, SourceLoaded(model.generation, index, side, result), _ => {
      @rabbita.none
    }).0,
  )
}

///|
test "anonymous forty-file PR only loads expanded and manually requested files" {
  let mut model = pump_source_fixture({
    ..source_prefetch_model(),
    auth: Anonymous(None),
  })
  for _ in 0..<40 {
    let pending = model.pull_sources.unwrap().pending
    assert_true(pending.length() <= 4)
    assert_true(pending[0].0 < 20)
    model = finish_source_fixture(model, pending[0])
  }
  assert_true(model.pull_sources.unwrap().pending.is_empty())
  assert_eq(model.pull_sources.unwrap().cursor, 0)
  guard model.phase is Showing(view) else { fail("view") }
  for file in view.files[20:] {
    assert_true(file.old_side is NotRequested)
    assert_true(file.new_side is NotRequested)
  }
  let opened = pump_source_fixture(
    update_load(model, OpenFile(1, 35), _ => @rabbita.none).0,
  )
  assert_true(opened.pull_sources.unwrap().pending == [(35, Old), (35, New)])
  let scrolled = pump_source_fixture(
    update_load(model, AutoExpandFile(1, "src/file30.mbt"), _ => @rabbita.none).0,
  )
  assert_true(scrolled.pull_sources.unwrap().pending == [(30, Old), (30, New)])
  let signed_in = pump_source_fixture(
    with_auth(
      model,
      SignedIn(login=Some("reviewer"), user_id=Some("1"), install_url=None),
    ),
  )
  assert_eq(signed_in.pull_sources.unwrap().pending.length(), 4)
  assert_true(
    signed_in.pull_sources.unwrap().pending.all(entry => entry.0 >= 20),
  )
}

///|
test "PR prefetch drains forty files without expanding or deriving later documents" {
  let mut model = pump_source_fixture(source_prefetch_model())
  let seen : Array[(Int32, SourceSide)] = []
  for _ in 0..<80 {
    let pending = model.pull_sources.unwrap().pending
    assert_true(pending.length() <= 4)
    let entry = pending[0]
    assert_false(seen.contains(entry))
    seen.push(entry)
    if seen.length() <= 40 {
      assert_true(entry.0 < 20)
    }
    model = finish_source_fixture(model, entry)
    assert_true(pump_source_fixture(model) == model)
  }
  assert_eq(seen.length(), 80)
  assert_true(model.pull_sources.unwrap().pending.is_empty())
  assert_true(
    update_load(
      model,
      SourceLoaded(1, 0, Old, Ok(("text/plain", b"duplicate"))),
      _ => @rabbita.none,
    ).0 ==
    model,
  )
  guard model.phase is Showing(view) else { fail("showing") }
  for index, file in view.files {
    assert_true(file.old_side is Ready(_))
    assert_true(file.new_side is Ready(_))
    assert_eq(file.expanded, index < 20)
    if index >= 20 {
      assert_true(file.diff_cache.entries.length() == 0)
      assert_true(file.diff_cache.highlights is None)
    }
  }
  let opened = update_load(model, AutoExpandFile(1, "src/file30.mbt"), _ => {
      @rabbita.none
    }).0
  guard opened.phase is Showing(opened_view) else { fail("opened") }
  assert_true(opened_view.files[30].expanded)
  assert_false(opened_view.files[30].diff_cache.entries.length() == 0)
  assert_true(opened_view.files[30].diff_cache.highlights is Some(_))
  assert_true(
    pump_source_fixture(opened).pull_sources.unwrap().pending.is_empty(),
  )
  assert_true(
    update_load(opened, AutoExpandFile(1, "src/file30.mbt"), _ => @rabbita.none).0 ==
    opened,
  )
}

///|
test "opening a distant PR file takes the next slots without duplicating active sides" {
  let model = pump_source_fixture(source_prefetch_model())
  assert_true(
    model.pull_sources.unwrap().pending ==
    [(0, Old), (0, New), (1, Old), (1, New)],
  )
  let opened = update_load(model, OpenFile(1, 35), _ => @rabbita.none).0
  let opened = pump_source_fixture(opened)
  assert_true(
    opened.pull_sources.unwrap().pending == model.pull_sources.unwrap().pending,
  )
  let next = finish_source_fixture(opened, (0, Old))
  assert_true(next.pull_sources.unwrap().pending.contains((35, Old)))
  let next = finish_source_fixture(next, (0, New))
  assert_true(next.pull_sources.unwrap().pending.contains((35, New)))
  let next = update_load(next, OpenFile(1, 35), _ => @rabbita.none).0
  assert_true(
    pump_source_fixture(next).pull_sources.unwrap().pending.length() == 4,
  )
}

///|
test "visibility and identity checks pause dispatch while retaining completed PR sides" {
  let model = pump_source_fixture(source_prefetch_model())
  for
    paused in [
      { ..model, page_visible: false, },
      with_auth(model, AuthChecking),
      { ..model, access: { ..model.access, identity_checking: true, }, },
    ] {
    let paused = finish_source_fixture(paused, (0, Old))
    assert_eq(paused.pull_sources.unwrap().pending.length(), 3)
    guard paused.phase is Showing(view) else { fail("view") }
    assert_true(view.files[0].old_side is Ready(_))
    let resumed = pump_source_fixture(
      with_auth({ ..paused, page_visible: true, }, Anonymous(None)),
    )
    assert_eq(resumed.pull_sources.unwrap().pending.length(), 4)
  }
}

///|
test "individual failures continue prefetch and rate limits block all demand" {
  let model = pump_source_fixture(source_prefetch_model())
  let failed = finish_source_fixture(
    model,
    (0, Old),
    result=Err(GitHubRequestError::GitHubRequestError("failed")),
  )
  assert_eq(failed.pull_sources.unwrap().pending.length(), 4)
  let error = @github_client.RateLimited(AuthenticatedRequests)
  let limited = finish_source_fixture(model, (0, Old), result=Err(error))
  assert_true(limited.source_pause == Some(AuthenticatedRequests))
  assert_eq(limited.pull_sources.unwrap().pending.length(), 3)
  let limited = restore_page_requests(limited, _ => @rabbita.none).0
  assert_true(limited.source_pause == Some(AuthenticatedRequests))
  let retry = update_load(limited, RetryFile(1, 0), _ => @rabbita.none).0
  assert_true(pump_source_fixture(retry) == limited)
  let opened = pump_source_fixture(
    update_load(limited, OpenFile(1, 35), _ => @rabbita.none).0,
  )
  assert_false(opened.pull_sources.unwrap().pending.contains((35, Old)))
  guard opened.phase is Showing(view) else { fail("view") }
  assert_true(view.files[35].old_side is Paused)
  assert_false(auto_expand_allowed(opened))
}

///|
test "prefetch includes renamed MoonBit sources and absent sides but excludes other files" {
  let model = source_prefetch_model(count=0)
  guard model.phase is Showing(empty) else { fail("view") }
  let files = [
    fixture_file("renamed.txt", "renamed", previous_filename="old.mbt"),
    fixture_file("added.mbtx", "added"),
    fixture_file("moon.pkg", "removed"),
    fixture_file("pkg.generated.mbti", "modified"),
    fixture_file("moon.mod", "modified"),
    fixture_file("README.md", "modified"),
  ]
  let view = @change.finish_change(
    empty.reference,
    empty.old_revision,
    empty.new_revision,
    "",
    "",
    empty.stats,
    files,
  )
  let mut next = pump_source_fixture(with_phase(model, Showing(view)))
  for _ in 0..<8 {
    next = finish_source_fixture(next, next.pull_sources.unwrap().pending[0])
  }
  assert_true(next.pull_sources.unwrap().pending.is_empty())
  guard next.phase is Showing(done) else { fail("done") }
  assert_eq(done.files[0].file.filename, "pkg.generated.mbti")
  assert_true(done.files[2].old_side is Ready([]))
  assert_true(done.files[3].new_side is Ready([]))
  assert_true(done.files[5].old_side is NotRequested)
  assert_true(done.files[5].new_side is NotRequested)
}

///|
test "PR admits every interface before sources and continues while an interface remains in flight" {
  let model = source_prefetch_model(count=0)
  guard model.phase is Showing(empty) else { fail("view") }
  let files = [fixture_file("src/main.mbt", "modified")]
  for index in 0..<25 {
    files.push(fixture_file("pkg\{index}/pkg.generated.mbti", "modified"))
  }
  let view = finish_change(
    empty.reference,
    empty.old_revision,
    empty.new_revision,
    "",
    "",
    empty.stats,
    files,
    expand_all_interfaces=true,
  )
  let mut next = pump_source_fixture(with_phase(model, Showing(view)))
  assert_true(
    next.pull_sources.unwrap().pending ==
    [(0, Old), (0, New), (1, Old), (1, New)],
  )
  for _ in 0..<50 {
    let pending = next.pull_sources.unwrap().pending
    assert_eq(pending.length(), 4)
    assert_true(pending.contains((0, Old)))
    if pending.contains((25, Old)) {
      break
    }
    next = finish_source_fixture(next, pending[1])
  }
  assert_true(next.pull_sources.unwrap().pending.contains((25, Old)))
  guard next.phase is Showing(loaded) else { fail("view") }
  for file in loaded.files[:25] {
    assert_true(file.expanded)
    assert_false(file.old_side is NotRequested)
    assert_false(file.new_side is NotRequested)
  }
  assert_false(loaded.files[25].expanded)
}

///|
test "automatic expansion respects Viewed manual collapse history and stale generations" {
  let model = source_prefetch_model()
  let collapsed = update_load(model, ToggleFile(1, 0), _ => @rabbita.none).0
  assert_true(
    update_load(collapsed, AutoExpandFile(1, "src/file0.mbt"), _ => {
      @rabbita.none
    }).0 ==
    collapsed,
  )
  let saved = save_route_memory(collapsed)
  let restored = restore_route_preferences(with_phase(saved, model.phase)).0
  assert_false(auto_expand_candidate(restored, 0))
  let reopened = update_load(restored, OpenFile(1, 0), _ => @rabbita.none).0
  guard reopened.phase is Showing(view) else { fail("view") }
  assert_false(view.files[0].manually_collapsed)
  let viewed = {
    ..model,
    viewed: {
      ..model.viewed,
      files: Array::makei(40, index => {
        ..empty_viewed_file(),
        state: if index == 30 {
          Some(Viewed)
        } else {
          None
        },
      }),
    },
  }
  assert_false(auto_expand_candidate(viewed, 30))
  for
    rejected in [
      AutoExpandFile(0, "src/file30.mbt"),
      AutoExpandFile(1, "absent.mbt"),
      SourceLoaded(0, 30, Old, Ok(("text/plain", b"stale"))),
    ] {
    assert_true(update_load(model, rejected, _ => @rabbita.none).0 == model)
  }
  let auto = update_load(model, AutoExpandFile(1, "src/file30.mbt"), _ => {
      @rabbita.none
    }).0
  assert_true(auto.viewed == model.viewed)
  for
    paused in [
      { ..model, navigation: { ..model.navigation, restore_position: true, }, },
      { ..model, page_visible: false, },
      with_auth(model, AuthChecking),
    ] {
    assert_true(
      update_load(paused, AutoExpandFile(1, "src/file30.mbt"), _ => {
        @rabbita.none
      }).0 ==
      paused,
    )
  }
  let left = pump_source_fixture({
    ..auto,
    phase: Idle,
    route: None,
    generation: 2,
  })
  assert_true(left.pull_sources is None)
  let commit = {
    ..model,
    phase: Showing({
      ..view,
      reference: { ..view.reference, target: Commit("a".repeat(40)), },
    }),
  }
  assert_true(pump_source_fixture(commit).pull_sources is None)
  assert_false(auto_expand_candidate(commit, 30))
}

///|
test "automatic expansion never records a manual Viewed interaction" {
  let model = viewed_interaction_model()
  guard model.phase is Showing(view) else { fail("view") }
  let file = { ..view.files[1], expanded: false, }
  let model = with_phase(model, Showing(set_file_state(view, 1, file)))
  let expanded = update(
      model,
      Load(AutoExpandFile(model.generation, file.file.filename)),
      _ => @rabbita.none,
    ).model
  assert_false(expanded.viewed.files[1].touched)
  assert_eq(expanded.viewed.files[1].expansion_revision, 0)
  guard expanded.phase is Showing(view) else { fail("expanded") }
  assert_true(view.files[1].expanded)
}

///|
test "prefetch validates binary byte and line budgets without deriving collapsed files" {
  for
    bytes in [
      b"a\x00b",
      Bytes::make(1048577, b'x'),
      @utf8.encode("line\n".repeat(20001)),
    ] {
    let model = source_prefetch_model()
    guard model.phase is Showing(view) else { fail("view") }
    let model = with_phase(
      model,
      Showing(
        set_file_state(view, 30, { ..view.files[30], old_side: Loading, }),
      ),
    )
    let next = update_load(
        model,
        SourceLoaded(1, 30, Old, Ok(("text/plain", bytes))),
        _ => @rabbita.none,
      ).0
    guard next.phase is Showing(done) else { fail("done") }
    assert_true(done.files[30].old_side is CannotRender(_, _))
    assert_false(done.files[30].expanded)
    assert_eq(done.files[30].diff_cache.entries.length(), 0)
    assert_true(done.files[30].diff_cache.highlights is None)
  }
}

///|
test "an unavailable identity service retains anonymous PR reads while expired accounts pause" {
  let model = source_prefetch_model()
  let failed = with_auth(model, AuthFailed("Identity check unavailable"))
  let next = pump_source_fixture(failed)
  assert_eq(next.pull_sources.unwrap().pending.length(), 4)
  assert_true(auto_expand_allowed(next))
  let expired = pump_source_fixture({
    ..failed,
    last_authenticated_user_id: Some("previous"),
  })
  assert_true(expired.pull_sources.unwrap().pending.is_empty())
  assert_false(auto_expand_allowed(expired))
}

///|
test "restoring collapsed in-flight sides preserves admitted slots behind the prefetch cursor" {
  let mut model = pump_source_fixture(source_prefetch_model())
  for _ in 0..<40 {
    model = finish_source_fixture(model, model.pull_sources.unwrap().pending[0])
  }
  let state = model.pull_sources.unwrap()
  assert_true(state.cursor > 20)
  model = update_load(model, ToggleFile(1, 20), _ => @rabbita.none).0
  model = update_load(model, ToggleFile(1, 20), _ => @rabbita.none).0
  let model = pause_source_loading(model, AuthenticatedRequests)
  let restored = restore_page_requests(model, _ => @rabbita.none).0
  assert_true(restored.pull_sources.unwrap().pending == state.pending)
  assert_eq(restored.pull_sources.unwrap().cursor, state.cursor)
  let completed = finish_source_fixture(restored, (20, Old))
  assert_eq(completed.pull_sources.unwrap().pending.length(), 3)
  guard completed.phase is Showing(view) else { fail("view") }
  assert_false(view.files[20].expanded)
  assert_true(view.files[20].old_side is Ready(_))
}

///|
test "PR history waits for snapshot confirmation before restoring geometry and focus" {
  let model = source_prefetch_model(count=0)
  assert_true(page_layout_ready(model))
  let checking = { ..model, access: { ..model.access, freshness: Checking, }, }
  assert_false(page_layout_ready(checking))
  assert_false(page_layout_ready(with_auth(model, AuthChecking)))
  let failed = {
    ..model,
    access: { ..model.access, freshness: Unavailable("offline"), },
  }
  assert_true(page_layout_ready(failed))
  let pending = {
    ..source_prefetch_model(),
    navigation: { ..model.navigation, restore_position: true, },
  }
  let opened = update_load(pending, OpenFile(1, 30), _ => @rabbita.none).0
  assert_false(opened.navigation.restore_position)
}
