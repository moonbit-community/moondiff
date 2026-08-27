///|
test "fallback text and section titles keep location responsibilities separate" {
  assert_eq(
    fallback_reason_text(SyntaxPositionsOutOfBounds(sides=[Old, New])),
    "syntax positions out of bounds on the old and new sides",
  )
  assert_eq(
    fallback_reason_text(SyntaxPositionsOutOfBounds(sides=[New])),
    "syntax positions out of bounds on the new side",
  )
  let fragment : @model.DiffFragment = {
    document: { hunks: [] },
    fallbacks: [],
  }
  assert_eq(
    section_title(
      3,
      Matched(old={ start: 1, len: 2 }, new={ start: 3, len: 2 }, diff=fragment),
    ),
    "[section #4 matched] old lines 2-3; new lines 4-5\n",
  )
}

///|
test "top-level renderer keeps fallback-only fragments visible" {
  let fragment : @model.DiffFragment = {
    document: { hunks: [] },
    fallbacks: [GraphLimitExceeded(limit=5)],
  }
  let top : @model.TopLevelDiff = {
    sections: [
      Matched(
        old={ start: 10, len: 2 },
        new={ start: 20, len: 2 },
        diff=fragment,
      ),
    ],
    old_order: [0],
    new_order: [0],
    reordered: false,
  }
  let rendered = render_top_level_document(
    "old.mbt",
    "new.mbt",
    top,
    Options::new(),
    12,
    22,
  )
  assert_true(
    rendered.has_prefix(
      "[section #1 matched] old lines 11-12; new lines 21-22\n",
    ),
  )
  assert_true(
    rendered.contains("note: fallback to tokdiff (graph limit exceeded (5))"),
  )
  assert_false(rendered.contains("--- old.mbt"))
}
