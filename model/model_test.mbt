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
  let document : @model.DiffDocument = {
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
test "public fallback metadata remains constructible and matchable" {
  let fallback : @model.FallbackInfo = {
    reason: ParseError(sides=[Old], detail="old: parse error"),
    scope: WholeFile,
  }
  assert_true(
    fallback
    is {
      reason: ParseError(sides=[Old], detail="old: parse error"),
      scope: WholeFile,
    },
  )
  guard fallback.reason is ParseError(sides~, ..) else {
    fail("expected parse-error metadata")
  }
  let _ : ArrayView[@model.DiffSide] = sides
}
