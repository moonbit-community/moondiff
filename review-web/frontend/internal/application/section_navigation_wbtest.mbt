///|
test "navigation eligibility follows the current semantic cache and Viewed state" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for algorithm in [@change.LexicalAlgorithm, AstAlgorithm] {
    let api = fixture_file("target.mbt", "modified")
    let raw = ready_test_file(api, ["fn target() { 1 }"], ["fn target() { 2 }"])
    let view = {
      ..diff_test_view([api]),
      reference: pull_reference("a", "b", "1"),
    }
    let pending = {
      ..diff_test_model(set_file_state(view, 0, raw)),
      diff_algorithm: algorithm,
    }
    assert_false(file_navigation_enabled(pending, 0))
    let cached = ensure_file_document(raw, algorithm)
    let ready = { ..pending, phase: Showing(set_file_state(view, 0, cached)), }
    assert_true(file_navigation_enabled(ready, 0))
    let loading = {
      ..ready,
      phase: Showing(set_file_state(view, 0, { ..cached, new_side: Loading, })),
    }
    assert_false(file_navigation_enabled(loading, 0))
    assert_false(file_navigation_enabled(ready, -1))
    assert_false(file_navigation_enabled(ready, 1))
    let (section_closed, _) = update_load(
      ready,
      ToggleSection(ready.generation, 0, "target"),
      emit,
    )
    assert_true(file_navigation_enabled(section_closed, 0))
    let (file_closed, _) = update_load(
      section_closed,
      ToggleFile(ready.generation, 0),
      emit,
    )
    assert_false(file_navigation_enabled(file_closed, 0))
    assert_true(
      update_load(
        file_closed,
        NavigateChange(ready.generation, 0, "target", 0, 1),
        emit,
      ).0 ==
      file_closed,
    )
    for state in [@protocol.Viewed, Unviewed, Dismissed] {
      let marked = {
        ..section_closed,
        viewed: {
          ..section_closed.viewed,
          files: [{ ..empty_viewed_file(), state: Some(state), }],
        },
      }
      assert_eq(file_navigation_enabled(marked, 0), state != Viewed)
      let (navigated, _) = update_load(
        marked,
        NavigateChange(marked.generation, 0, "target", 0, 1),
        emit,
      )
      if state == Viewed {
        assert_true(navigated == marked)
      } else {
        assert_eq(collapsed_sections(navigated), [])
      }
    }
    // A filtered cache must be recomputed; the unfiltered entry is not a target.
    assert_false(
      file_navigation_enabled({ ..ready, ignore_comments: true, }, 0),
    )
    for
      (name, old, new, ignore_comments, ignore_tests) in [
        ("same.mbt", "fn same() { 1 }", "fn same() { 1 }", false, false),
        ("plain.txt", "old", "new", false, false),
        ("invalid.mbt", "fn broken( {", "fn broken( }", false, false),
        (
          "comments.mbt", "// old\nfn same() { 1 }", "// new\nfn same() { 1 }", true,
          false,
        ),
        (
          "ignored_test.mbt", "fn target() { 1 }", "fn target() { 2 }", false, true,
        ),
      ] {
      let file = ensure_file_document(
        ready_test_file(fixture_file(name, "modified"), [old], [new]),
        algorithm,
        ignore_comments~,
        ignore_tests~,
      )
      let empty = {
        ..ready,
        phase: Showing(set_file_state(view, 0, file)),
        ignore_comments,
        ignore_tests,
      }
      assert_false(file_navigation_enabled(empty, 0), msg=name)
    }
  }
}
