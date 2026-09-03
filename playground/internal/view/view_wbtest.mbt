///|
fn fixture_file(
  filename : String,
  status : String,
  previous_filename? : String,
) -> ApiFile {
  {
    filename,
    previous_filename,
    status,
    additions: 1,
    deletions: 2,
    changes: 3,
    patch: None,
  }
}

///|
test "diff notices distinguish Whole and section-local fallbacks" {
  guard diff_notice([ParseError(sides=[Old], detail="old: parse error")], true)
    is Some(complete) else {
    fail("expected a complete fallback notice")
  }
  assert_eq(complete.class_name, "diff-notice fallback")
  assert_eq(complete.label, "Lexical fallback")
  assert_true(complete.message.contains("this entire file"))
  assert_true(complete.message.contains("old: parse error"))

  guard diff_notice([SyntaxPositionsOutOfBounds(sides=[Old, New])], true)
    is Some(position_complete) else {
    fail("expected a complete syntax-position fallback notice")
  }
  assert_true(
    position_complete.message.contains(
      "syntax positions out of bounds on the old and new sides",
    ),
  )

  guard diff_notice([GraphLimitExceeded(limit=3_000_000)], false)
    is Some(partial) else {
    fail("expected a section-local fallback notice")
  }
  assert_eq(partial.class_name, "diff-notice partial-fallback")
  assert_eq(partial.label, "Section lexical fallback")
  assert_true(partial.message.contains("Only this semantic section"))
  assert_true(partial.message.contains("graph limit exceeded"))

  guard diff_notice([SyntaxPositionsOutOfBounds(sides=[New])], false)
    is Some(position_partial) else {
    fail("expected a section-local syntax-position fallback notice")
  }
  assert_true(
    position_partial.message.contains(
      "syntax positions out of bounds on the new side",
    ),
  )
  assert_true(position_partial.message.contains("Only this semantic section"))

  assert_true(diff_notice([], true) is None)
  assert_true(diff_notice([], false) is None)
}

///|
fn ready_test_file(
  file : ApiFile,
  old : Array[String],
  new : Array[String],
  expanded? : Bool = true,
) -> FileState {
  {
    file,
    diff_mode: file_diff_mode(file),
    expanded,
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: DiffCache::empty(),
  }
}

///|
fn test_file_tree_state(
  search_query? : String = "",
  selected_statuses? : Array[String] = [],
  collapsed_directories? : Array[String] = [],
) -> FileTreeState {
  {
    drawer_open: false,
    search_open: !search_query.is_empty(),
    search_query,
    selected_statuses,
    collapsed_directories,
    selected_file_index: None,
    preferred_width: 320,
  }
}

///|
fn file_tree_test_rows() -> Array[FileState] {
  [
    ready_test_file(fixture_file("src/lib/a.mbt", "modified"), [], []),
    ready_test_file(fixture_file("README.md", "added"), [], []),
    ready_test_file(
      fixture_file(
        "src/lib/b.mbt",
        "renamed",
        previous_filename="legacy/OLD_B.mbt",
      ),
      [],
      [],
    ),
    ready_test_file(fixture_file("src/main.mbt", "removed"), [], []),
  ]
}

///|
fn file_tree_row_summary(row : FileTreeRow) -> String {
  match row {
    TreeDirectory(path~, depth~, ..) => "D:\{path}:\{depth}"
    TreeFile(index~, path~, depth~, ..) => "F:\{index}:\{path}:\{depth}"
  }
}

///|
fn file_tree_row_depth(row : FileTreeRow) -> Int {
  match row {
    TreeDirectory(depth~, ..) | TreeFile(depth~, ..) => depth
  }
}

///|
test "file tree expands interleaved paths depth first with stable siblings" {
  let files = file_tree_test_rows()
  let rows = build_file_tree(files)
  assert_eq(file_tree_statuses(files), [
    "modified", "added", "renamed", "removed",
  ])
  assert_eq(rows.map(file_tree_row_summary), [
    "D:src:0", "D:src/lib:1", "F:0:src/lib/a.mbt:2", "F:2:src/lib/b.mbt:2", "F:3:src/main.mbt:1",
    "F:1:README.md:0",
  ])
  let directories : Array[String] = []
  let mut previous_depth = -1
  for row in rows {
    let depth = file_tree_row_depth(row)
    assert_true(depth <= previous_depth + 1)
    previous_depth = depth
    if row is TreeDirectory(path~, ..) {
      assert_false(directories.contains(path))
      directories.push(path)
    }
  }
  assert_eq(directories, ["src", "src/lib"])
  guard rows[3]
    is TreeFile(
      name="b.mbt",
      path="src/lib/b.mbt",
      previous_path=Some(previous),
      ..
    ) else {
    fail("expected the renamed file to use its new tree path")
  }
  assert_eq(previous, "legacy/OLD_B.mbt")
}

///|
test "file tree collapse hides descendants without changing row order" {
  let rows = build_file_tree(file_tree_test_rows())
  let projection = project_file_tree(
    rows,
    test_file_tree_state(collapsed_directories=["src"]),
  )
  assert_eq(projection.matching_count, 4)
  assert_eq(projection.visible_rows.map(file_tree_row_summary), [
    "D:src:0", "F:1:README.md:0",
  ])
}

///|
test "file tree search is case insensitive and includes renamed ancestors" {
  let rows = build_file_tree(file_tree_test_rows())
  let state = test_file_tree_state(search_query="old_b.MBT", collapsed_directories=[
    "src",
  ])
  let renamed = project_file_tree(rows, state)
  assert_eq(renamed.matching_count, 1)
  assert_eq(renamed.visible_rows.map(file_tree_row_summary), [
    "D:src:0", "D:src/lib:1", "F:2:src/lib/b.mbt:2",
  ])

  let current_path = test_file_tree_state(search_query="LIB/A.MBT")
  assert_eq(project_file_tree(rows, current_path).matching_count, 1)
}

///|
test "file tree status filters use OR and combine with search using AND" {
  let rows = build_file_tree(file_tree_test_rows())
  let statuses = test_file_tree_state(selected_statuses=["added", "removed"])
  let status_projection = project_file_tree(rows, statuses)
  assert_eq(status_projection.matching_count, 2)
  assert_eq(status_projection.visible_rows.map(file_tree_row_summary), [
    "D:src:0", "F:3:src/main.mbt:1", "F:1:README.md:0",
  ])

  let combined = test_file_tree_state(search_query="SRC/MAIN", selected_statuses=[
    "added", "removed",
  ])
  let combined_projection = project_file_tree(rows, combined)
  assert_eq(combined_projection.matching_count, 1)
  assert_eq(combined_projection.visible_rows.map(file_tree_row_summary), [
    "D:src:0", "F:3:src/main.mbt:1",
  ])

  let empty = test_file_tree_state(search_query="missing", selected_statuses=[
    "renamed",
  ])
  let empty_projection = project_file_tree(rows, empty)
  assert_eq(empty_projection.matching_count, 0)
  assert_true(empty_projection.visible_rows.is_empty())
}

///|
test "file tree projection scales to the maximum supported file count" {
  let files : Array[FileState] = []
  for index in 0..<3000 {
    files.push(
      ready_test_file(
        fixture_file("src/group-\{index}/nested/file-\{index}.mbt", "modified"),
        [],
        [],
      ),
    )
  }
  let rows = build_file_tree(files)
  let missing = project_file_tree(
    rows,
    test_file_tree_state(search_query="does-not-exist"),
  )
  assert_eq(missing.matching_count, 0)
  assert_true(missing.visible_rows.is_empty())

  let last = project_file_tree(
    rows,
    test_file_tree_state(search_query="file-2999.mbt"),
  )
  assert_eq(last.matching_count, 1)
  assert_eq(last.visible_rows.map(file_tree_row_summary), [
    "D:src:0", "D:src/group-2999:1", "D:src/group-2999/nested:2", "F:2999:src/group-2999/nested/file-2999.mbt:3",
  ])
}

///|
test "line and MoonBit caches retain distinct semantic variants" {
  let text_file = ensure_file_document(
    ready_test_file(fixture_file("README.md", "modified"), ["old"], ["new"]),
    LexicalAlgorithm,
  )
  guard text_file.diff_cache.get(Line) is Some(Line(line_document)) else {
    fail("expected a line-diff cache")
  }
  assert_false(line_document.hunks.is_empty())

  let moonbit_file = ensure_file_document(
    ready_test_file(
      fixture_file("src/reorder.mbt", "modified"),
      ["fn first() {}", "fn second() {}"],
      ["fn second() {}", "fn first() {}"],
    ),
    AstAlgorithm,
  )
  guard moonbit_file.diff_cache.get(MoonBit(AstAlgorithm, false, false))
    is Some(MoonBit(document=TopLevel(top), status=Reordered)) else {
    fail("expected a semantic reorder cache")
  }
  assert_true(top.reordered)
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [1, 0])
  assert_true(
    top.sections.all(section => {
      semantic_section_fragment(section).document.hunks.is_empty()
    }),
  )
}

///|
test "semantic section titles format declaration contexts" {
  let fragment : @mbtdiff.DiffFragment = {
    document: { hunks: [], },
    fallbacks: [],
  }
  assert_eq(
    semantic_section_title(
      0,
      Matched(
        old={ start: 0, len: 1, },
        new={ start: 1, len: 1, },
        old_context=Some("fn target() {"),
        new_context=Some("fn target() {"),
        diff=fragment,
      ),
    ),
    "Section #1 · Matched · old line 1 · new line 2 · fn target() {",
  )
  assert_eq(
    semantic_section_title(
      1,
      Matched(
        old={ start: 2, len: 1, },
        new={ start: 3, len: 1, },
        old_context=Some("fn old_name() {}"),
        new_context=Some("fn new_name() {}"),
        diff=fragment,
      ),
    ),
    "Section #2 · Matched · old line 3 · new line 4 · old: fn old_name() {} → new: fn new_name() {}",
  )
  assert_eq(
    semantic_section_title(
      2,
      Deleted(
        old={ start: 4, len: 1, },
        old_context=Some("fn removed() {}"),
        diff=fragment,
      ),
    ),
    "Section #3 · Deleted · old line 5 · new side absent · fn removed() {}",
  )
  assert_eq(
    semantic_section_title(
      3,
      Inserted(
        new={ start: 5, len: 1, },
        new_context=Some("fn inserted() {}"),
        diff=fragment,
      ),
    ),
    "Section #4 · Inserted · old side absent · new line 6 · fn inserted() {}",
  )
  assert_eq(
    semantic_section_title(
      4,
      Matched(
        old={ start: 6, len: 1, },
        new={ start: 6, len: 1, },
        old_context=None,
        new_context=None,
        diff=fragment,
      ),
    ),
    "Section #5 · Matched · old line 7 · new line 7",
  )
}

///|
#warnings("-alert_unstable")
test "AST structural-empty view preserves section fallback notices" {
  let fragment : @mbtdiff.DiffFragment = {
    document: { hunks: [], },
    fallbacks: [GraphLimitExceeded(limit=23)],
  }
  let document : @mbtdiff.DiffDocument = TopLevel({
    sections: [
      Matched(
        old={ start: 0, len: 1, },
        new={ start: 0, len: 1, },
        old_context=Some("fn target() {}"),
        new_context=Some("fn target() {}"),
        diff=fragment,
      ),
    ],
    old_order: [0],
    new_order: [0],
    reordered: false,
  })
  let base = ready_test_file(
    fixture_file("src/target.mbt", "modified"),
    ["fn target() {}"],
    ["fn target( ) {}"],
  )
  let file = {
    ..base,
    diff_cache: base.diff_cache.put(
      MoonBit(AstAlgorithm, false, false),
      MoonBit(document~, status=NoStructuralChanges),
    ),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      file_diff_view(
        file,
        0,
        0,
        Split,
        AstAlgorithm,
        false,
        false,
        @comments.initial_review_state(),
        emit,
      ),
    )
  })
  assert_true(rendered.contains("Section #1 · Matched"), msg=rendered)
  assert_true(rendered.contains("partial-fallback"), msg=rendered)
  assert_true(rendered.contains("graph limit exceeded (23)"), msg=rendered)
  assert_true(rendered.contains("structural-empty"), msg=rendered)
  assert_true(rendered.contains("No structural changes found."), msg=rendered)
  assert_true(
    rendered.find("partial-fallback").unwrap_or(-1) <
    rendered.find("structural-empty").unwrap_or(-1),
    msg=rendered,
  )
  assert_false(rendered.contains("hunk-header"), msg=rendered)
  assert_false(rendered.contains("<table"), msg=rendered)
}

///|
#warnings("-alert_unstable")
test "AST structural-empty view without fallback keeps its original DOM" {
  let document : @mbtdiff.DiffDocument = Whole({
    document: { hunks: [], },
    fallbacks: [],
  })
  let base = ready_test_file(
    fixture_file("src/formatted.mbt", "modified"),
    ["fn formatted() {}"],
    ["fn formatted( ) {}"],
  )
  let file = {
    ..base,
    diff_cache: base.diff_cache.put(
      MoonBit(AstAlgorithm, false, false),
      MoonBit(document~, status=NoStructuralChanges),
    ),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      file_diff_view(
        file,
        0,
        0,
        Split,
        AstAlgorithm,
        false,
        false,
        @comments.initial_review_state(),
        emit,
      ),
    )
  })
  assert_eq(
    rendered, "<div class=\"file-message structural-empty\"><p>No structural changes found. Switch to Lexical to view text changes.</p></div>",
  )
}
