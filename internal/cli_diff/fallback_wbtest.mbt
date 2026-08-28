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
    document: { hunks: [], },
    fallbacks: [],
  }
  assert_eq(
    section_title(
      3,
      Matched(
        old={ start: 1, len: 2, },
        new={ start: 3, len: 2, },
        old_context=Some("fn target() {"),
        new_context=Some("fn target() {"),
        diff=fragment,
      ),
    ),
    "[section #4 matched] old lines 2-3; new lines 4-5 · fn target() {\n",
  )
  assert_eq(
    section_title(
      0,
      Matched(
        old={ start: 0, len: 1, },
        new={ start: 1, len: 1, },
        old_context=Some("fn old_name() {}"),
        new_context=Some("fn new_name() {}"),
        diff=fragment,
      ),
    ),
    "[section #1 matched] old line 1; new line 2 · old: fn old_name() {} → new: fn new_name() {}\n",
  )
  assert_eq(
    section_title(
      1,
      Deleted(
        old={ start: 2, len: 1, },
        old_context=Some("fn removed() {}"),
        diff=fragment,
      ),
    ),
    "[section #2 deleted] old line 3; new absent · fn removed() {}\n",
  )
  assert_eq(
    section_title(
      2,
      Inserted(
        new={ start: 4, len: 1, },
        new_context=Some("fn inserted() {}"),
        diff=fragment,
      ),
    ),
    "[section #3 inserted] old absent; new line 5 · fn inserted() {}\n",
  )
  assert_eq(
    section_title(
      3,
      Matched(
        old={ start: 5, len: 1, },
        new={ start: 5, len: 1, },
        old_context=None,
        new_context=None,
        diff=fragment,
      ),
    ),
    "[section #4 matched] old line 6; new line 6\n",
  )
}

///|
test "top-level renderer keeps fallback-only fragments visible" {
  let fragment : @model.DiffFragment = {
    document: { hunks: [], },
    fallbacks: [GraphLimitExceeded(limit=5)],
  }
  let top : @model.TopLevelDiff = {
    sections: [
      Matched(
        old={ start: 10, len: 2, },
        new={ start: 20, len: 2, },
        old_context=Some("fn target() {"),
        new_context=Some("fn target() {"),
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
      "[section #1 matched] old lines 11-12; new lines 21-22 · fn target() {\n",
    ),
  )
  assert_true(
    rendered.contains("note: fallback to tokdiff (graph limit exceeded (5))"),
  )
  assert_false(rendered.contains("--- old.mbt"))
}

///|
test "section renderer appends declaration context to every hunk" {
  let fragment : @model.DiffFragment = {
    document: {
      hunks: [
        { old_start: 0, old_len: 1, new_start: 0, new_len: 1, blocks: [], },
        { old_start: 7, old_len: 1, new_start: 9, new_len: 1, blocks: [], },
      ],
    },
    fallbacks: [],
  }
  let section : @model.DiffSection = Matched(
    old={ start: 10, len: 10, },
    new={ start: 20, len: 10, },
    old_context=Some("fn target() {"),
    new_context=Some("fn target() {"),
    diff=fragment,
  )
  assert_eq(
    render_section_fragment(
      "old.mbt",
      "new.mbt",
      0,
      section,
      Options::new(),
      20,
      30,
    ),
    (
      #|[section #1 matched] old lines 11-20; new lines 21-30 · fn target() {
      #|--- old.mbt: lines 11-20
      #|+++ new.mbt: lines 21-30
      #|@@ -11 +21 @@ fn target() {
      #|@@ -18 +30 @@ fn target() {
      #|
    ),
  )
}
