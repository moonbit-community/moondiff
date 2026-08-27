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
  let fragment : @model.DiffFragment = { rows: [], fallbacks: [] }
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
    rows: [],
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

///|
fn compactor_line(
  index : Int,
  text : String,
  kind? : @model.DiffSegmentKind = Unchanged,
) -> @model.DiffLine {
  { index, segments: [{ kind, text }] }
}

///|
test "semantic compactor selects only Changed cores and derives cursors" {
  let rows : ArrayView[@model.DiffRow] = [
    Context({ old_index: 0, new_index: 0, text: "zero" }),
    Context({ old_index: 1, new_index: 1, text: "one" }),
    Neutral(
      Paired(compactor_line(2, "old format"), compactor_line(2, "new format")),
    ),
    Context({ old_index: 3, new_index: 3, text: "three" }),
    Changed(
      Paired(compactor_line(4, "old value"), compactor_line(4, "new value")),
    ),
    Neutral(
      Paired(
        compactor_line(5, "// old", kind=Ignored),
        compactor_line(5, "// new", kind=Ignored),
      ),
    ),
    Context({ old_index: 6, new_index: 6, text: "six" }),
  ]
  let document = compact_semantic_rows(rows, 1)
  guard document.hunks
    is [
      {
        old_start: 3,
        old_len: 3,
        new_start: 3,
        new_len: 3,
        rows: [Context(_), Changed(_), Neutral(_)],
      },
    ] else {
    fail("expected one context window with filtered neutral context")
  }
  assert_true(compact_semantic_rows(rows[0:4], 3).hunks.is_empty())

  let insertion = compact_semantic_rows(
    [
      Context({ old_index: 0, new_index: 0, text: "before" }),
      Changed(NewOnly(compactor_line(1, "inserted"))),
      Context({ old_index: 1, new_index: 2, text: "after" }),
    ],
    0,
  )
  guard insertion.hunks
    is [{ old_start: 1, old_len: 0, new_start: 1, new_len: 1, .. }] else {
    fail("expected insertion cursor ranges from the complete row prefix")
  }
}
