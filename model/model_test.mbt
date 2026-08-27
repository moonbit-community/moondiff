///|
fn test_line(index : Int, text : String) -> @model.DiffLine {
  {
    index,
    segments: if text.is_empty() {
      []
    } else {
      [{ kind: Unchanged, text }]
    },
  }
}

///|
test "public row and hunk views are read-only and rebase together" {
  let old = test_line(2, "old")
  let new = test_line(3, "new")
  let document : @model.HunkDocument = {
    hunks: [
      {
        old_start: 1,
        old_len: 3,
        new_start: 1,
        new_len: 4,
        rows: [
          Context({ old_index: 1, new_index: 1, text: "same" }),
          Changed(Paired(old, new)),
          Neutral(NewOnly(test_line(4, "formatting"))),
        ],
      },
    ],
  }
  let _ : ArrayView[@model.DiffHunk] = document.hunks
  guard document.hunks is [{ rows, .. }] else { fail("expected one hunk") }
  let _ : ArrayView[@model.DiffRow] = rows
  let rebased = document.rebase(10, 20)
  guard rebased.hunks
    is [
      {
        old_start: 11,
        new_start: 21,
        rows: [
          Context({ old_index: 11, new_index: 21, .. }),
          Changed(Paired(rebased_old, rebased_new)),
          Neutral(NewOnly(rebased_neutral)),
        ],
        ..,
      },
    ] else {
    fail("expected all row indexes to be rebased")
  }
  assert_eq((rebased_old.index, rebased_new.index), (12, 23))
  assert_eq(rebased_neutral.index, 24)
  assert_eq(rebased_old.text(), "old")
}

///|
test "all non-context row shapes remain explicit" {
  let line = test_line(0, "value")
  let rows : ArrayView[@model.DiffRow] = [
    Changed(Paired(line, line)),
    Changed(OldOnly(line)),
    Changed(NewOnly(line)),
    Neutral(Paired(line, line)),
    Neutral(OldOnly(line)),
    Neutral(NewOnly(line)),
  ]
  assert_eq(rows.length(), 6)
}

///|
test "fragment rows and fallback metadata remain stable read-only views" {
  let reason : @model.FallbackReason = ParseError(
    sides=[Old],
    detail="old: parse error",
  )
  let fragment : @model.DiffFragment = {
    rows: [Changed(OldOnly(test_line(0, "broken")))],
    fallbacks: [reason],
  }
  let _ : ArrayView[@model.DiffRow] = fragment.rows
  let _ : ArrayView[@model.FallbackReason] = fragment.fallbacks
  assert_true(
    fragment.fallbacks is [ParseError(sides=[Old], detail="old: parse error")],
  )
  let row_copy = fragment.rows.to_owned()
  row_copy.clear()
  assert_eq(fragment.rows.length(), 1)
}

///|
test "semantic documents expose all section variants and both orders" {
  let empty : @model.DiffFragment = { rows: [], fallbacks: [] }
  let document : @model.DiffDocument = TopLevel({
    sections: [
      Matched(old={ start: 0, len: 2 }, new={ start: 4, len: 2 }, diff=empty),
      Deleted(old={ start: 2, len: 2 }, diff=empty),
      Inserted(new={ start: 0, len: 4 }, diff=empty),
    ],
    old_order: [0, 1],
    new_order: [2, 0],
    reordered: false,
  })
  guard document is TopLevel(top) else { fail("expected a top-level document") }
  let _ : ArrayView[@model.DiffSection] = top.sections
  let _ : ArrayView[Int] = top.old_order
  let _ : ArrayView[Int] = top.new_order
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [2, 0])
}

///|
test "Whole owns its complete primary fragment" {
  let fragment : @model.DiffFragment = {
    rows: [],
    fallbacks: [GraphLimitExceeded(limit=7)],
  }
  let document : @model.DiffDocument = Whole(fragment)
  guard document is Whole(actual) else { fail("expected Whole") }
  assert_true(actual.rows.is_empty())
  assert_true(actual.fallbacks is [GraphLimitExceeded(limit=7)])
}
