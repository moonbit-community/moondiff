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
