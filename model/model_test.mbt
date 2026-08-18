///|
test "public document model owns pure document methods" {
  let line : @model.DiffLine = {
    index: 2,
    segments: [
      { kind: Unchanged, text: "let value = " },
      { kind: Changed, text: "new" },
    ],
  }
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
}
