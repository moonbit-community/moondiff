///|
test "public document model owns pure document methods" {
  let line : @model.DiffLine = {
    index: 2,
    segments: [
      { kind: Unchanged, text: "let value = " },
      { kind: Changed, text: "new" },
    ],
  }
  let _ : ArrayView[@model.DiffSegment] = line.segments
  assert_eq(line.text(), "let value = new")
  let document : @model.HunkDocument = {
    hunks: [
      {
        old_start: 2,
        old_len: 1,
        new_start: 3,
        new_len: 1,
        blocks: [ChangeBlock([NewOnly(line)])],
      },
    ],
  }
  let _ : ArrayView[@model.DiffHunk] = document.hunks
  guard document.hunks is [source_hunk] else {
    fail("expected one source hunk")
  }
  let _ : ArrayView[@model.DiffBlock] = source_hunk.blocks
  guard source_hunk.blocks is [ChangeBlock(source_rows)] else {
    fail("expected one source change block")
  }
  let _ : ArrayView[@model.DiffRow] = source_rows
  let rebased = document.rebase(10, 20)
  guard rebased.hunks
    is [
      {
        old_start: 12,
        new_start: 23,
        blocks: [ChangeBlock([NewOnly(rebased_line)])],
        ..,
      },
    ] else {
    fail("expected all document indexes to be rebased")
  }
  assert_eq(rebased_line.index, 22)
  assert_eq(rebased_line.text(), line.text())
}

///|
test "all public block payloads are read-only views" {
  let context : @model.DiffBlock = ContextBlock([
    { old_index: 0, new_index: 0, text: "same" },
  ])
  let changed : @model.DiffBlock = ChangeBlock([])
  let ignored : @model.DiffBlock = IgnoredBlock([])
  match context {
    ContextBlock(lines) => {
      let _ : ArrayView[@model.ContextLine] = lines
    }
    _ => fail("expected a context block")
  }
  match changed {
    ChangeBlock(rows) => {
      let _ : ArrayView[@model.DiffRow] = rows
    }
    _ => fail("expected a change block")
  }
  match ignored {
    IgnoredBlock(rows) => {
      let _ : ArrayView[@model.DiffRow] = rows
    }
    _ => fail("expected an ignored block")
  }
}

///|
test "fragment fallback metadata remains local and matchable" {
  let reason : @model.FallbackReason = ParseError(
    sides=[Old],
    detail="old: parse error",
  )
  let fragment : @model.DiffFragment = {
    document: { hunks: [] },
    fallbacks: [reason],
  }
  assert_true(
    fragment.fallbacks is [ParseError(sides=[Old], detail="old: parse error")],
  )
  guard fragment.fallbacks[0] is ParseError(sides~, ..) else {
    fail("expected parse-error metadata")
  }
  let _ : ArrayView[@model.DiffSide] = sides
  let syntax_positions : @model.FallbackReason = SyntaxPositionsOutOfBounds(sides=[
    Old,
    New,
  ])
  guard syntax_positions is SyntaxPositionsOutOfBounds(sides~) else {
    fail("expected syntax-position metadata")
  }
  assert_true(sides is [Old, New])
}

///|
test "semantic documents expose all section variants and both orders" {
  let empty : @model.DiffFragment = { document: { hunks: [] }, fallbacks: [] }
  let document : @model.DiffDocument = TopLevel({
    sections: [
      Matched(
        old={ start: 0, len: 2 },
        new={ start: 4, len: 2 },
        old_context=Some("fn old() {"),
        new_context=Some("fn new() {"),
        diff=empty,
      ),
      Deleted(
        old={ start: 2, len: 2 },
        old_context=Some("fn removed() {"),
        diff=empty,
      ),
      Inserted(
        new={ start: 0, len: 4 },
        new_context=Some("fn inserted() {"),
        diff=empty,
      ),
    ],
    old_order: [0, 1],
    new_order: [2, 0],
    reordered: false,
  })
  guard document is TopLevel(top) else { fail("expected a top-level document") }
  let sections = top.sections
  let _ : ArrayView[@model.DiffSection] = sections
  let _ : ArrayView[Int] = top.old_order
  let _ : ArrayView[Int] = top.new_order
  assert_true(
    sections
    is [
      Matched(
        old={ start: 0, len: 2 },
        new={ start: 4, len: 2 },
        old_context=Some("fn old() {"),
        new_context=Some("fn new() {"),
        ..
      ),
      Deleted(old={ start: 2, len: 2 }, old_context=Some("fn removed() {"), ..),
      Inserted(
        new={ start: 0, len: 4 },
        new_context=Some("fn inserted() {"),
        ..
      ),
    ],
  )
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [2, 0])
}

///|
test "Whole owns its primary fragment without a linear projection" {
  let fragment : @model.DiffFragment = {
    document: { hunks: [] },
    fallbacks: [GraphLimitExceeded(limit=7)],
  }
  let document : @model.DiffDocument = Whole(fragment)
  guard document is Whole(actual) else { fail("expected Whole") }
  assert_true(actual.document.hunks.is_empty())
  assert_true(actual.fallbacks is [GraphLimitExceeded(limit=7)])
}
