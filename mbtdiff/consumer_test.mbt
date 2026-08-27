///|
fn status_name(status : @mbtdiff.DiffStatus) -> String {
  match status {
    Identical => "identical"
    Changed => "changed"
    Reordered => "reordered"
    NoStructuralChanges => "no-structural-changes"
    IgnoredOnly => "ignored-only"
  }
}

///|
fn side_name(side : @mbtdiff.DiffSide) -> String {
  match side {
    Old => "old"
    New => "new"
  }
}

///|
fn stage_name(stage : @mbtdiff.ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level"
    SyntaxMatching => "syntax"
    IntralineMatching => "intraline"
  }
}

///|
fn fallback_name(reason : @mbtdiff.FallbackReason) -> String {
  match reason {
    ParseError(sides~, detail~) => "\{sides.map(side_name).join(",")}:\{detail}"
    SyntaxPositionsOutOfBounds(sides~) =>
      "syntax:\{sides.map(side_name).join(",")}"
    GraphLimitExceeded(limit~) => "graph:\{limit}"
    ComputationLimitExceeded(stage~, limit~) => "\{stage_name(stage)}:\{limit}"
  }
}

///|
fn segment_name(kind : @mbtdiff.DiffSegmentKind) -> String {
  match kind {
    Changed => "changed"
    Unchanged => "unchanged"
    Ignored => "ignored"
  }
}

///|
fn traverse_pair(pair : @mbtdiff.DiffLinePair) -> Int {
  let lines : Array[@mbtdiff.DiffLine] = match pair {
    Paired(old_line, new_line) => [old_line, new_line]
    OldOnly(line) | NewOnly(line) => [line]
  }
  let mut segments = 0
  for line in lines {
    let _ = (line.index, line.text())
    let _ : ArrayView[@mbtdiff.DiffSegment] = line.segments
    for segment in line.segments {
      let _ : @mbtdiff.DiffSegmentKind = segment.kind
      ignore(segment_name(segment.kind))
      segments += 1
    }
  }
  segments
}

///|
fn traverse_rows(rows : ArrayView[@mbtdiff.DiffRow]) -> Int {
  let mut segments = 0
  for row in rows {
    match row {
      Context(line) => {
        let _ : @mbtdiff.ContextLine = line
        let _ = (line.old_index, line.new_index, line.text)
      }
      Changed(pair) | Neutral(pair) => segments += traverse_pair(pair)
    }
  }
  segments
}

///|
fn fragment_of_section(section : @mbtdiff.DiffSection) -> @mbtdiff.DiffFragment {
  match section {
    Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
  }
}

///|
test "external consumer exhaustively matches the complete semantic result" {
  let result = @mbtdiff.diff(
    "fn first() { old_value() }\nfn removed() {}", "fn inserted() {}\nfn first() { new_value() }",
  )
  let _ : @mbtdiff.DiffResult = result
  let _ : @mbtdiff.DiffStatus = result.status()
  assert_eq(status_name(result.status()), "changed")
  let document : @mbtdiff.DiffDocument = result.document()
  guard document is TopLevel(top) else {
    fail("expected reliable top-level pairings")
  }
  let _ : @mbtdiff.TopLevelDiff = top
  let _ : ArrayView[@mbtdiff.DiffSection] = top.sections
  let _ : ArrayView[Int] = top.old_order
  let _ : ArrayView[Int] = top.new_order
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [2, 0])
  assert_eq(top.sections.length(), 3)

  let mut matched = 0
  let mut deleted = 0
  let mut inserted = 0
  let mut row_count = 0
  for section in top.sections {
    match section {
      Matched(old~, new~, diff~) => {
        let _ : @mbtdiff.LineRange = old
        let _ : @mbtdiff.LineRange = new
        let _ : @mbtdiff.DiffFragment = diff
        matched += 1
      }
      Deleted(old~, diff~) => {
        let _ = (old.start, old.len, diff.fallbacks)
        deleted += 1
      }
      Inserted(new~, diff~) => {
        let _ = (new.start, new.len, diff.fallbacks)
        inserted += 1
      }
    }
    let fragment = fragment_of_section(section)
    let _ : ArrayView[@mbtdiff.DiffRow] = fragment.rows
    row_count += fragment.rows.length()
    ignore(traverse_rows(fragment.rows))
  }
  assert_eq((matched, deleted, inserted), (1, 1, 1))
  assert_true(row_count >= 3)
}

///|
test "fallbacks are read from the fragment that degraded" {
  assert_eq(
    fallback_name(SyntaxPositionsOutOfBounds(sides=[Old, New])),
    "syntax:old,new",
  )
  let parsed = @mbtdiff.diff(
    "fn broken( {",
    "fn okay() {}",
    old_name="before.mbt",
  )
  guard parsed.document()
    is Whole({ rows, fallbacks: [ParseError(sides~, detail~)] }) else {
    fail("expected one Whole parse fallback")
  }
  assert_false(rows.is_empty())
  let _ : ArrayView[@mbtdiff.DiffSide] = sides
  assert_true(sides is [Old])
  assert_true(detail.contains("before.mbt"), msg=detail)
}

///|
test "copies of semantic views cannot mutate later accessor results" {
  let changed = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  guard changed.document() is TopLevel(top) else {
    fail("expected a top-level document")
  }
  let section_count = top.sections.length()
  let section_copy = top.sections.to_owned()
  section_copy.clear()
  guard changed.document() is TopLevel(later_top) else {
    fail("expected a stable top-level document")
  }
  assert_eq(later_top.sections.length(), section_count)

  guard later_top.sections is [Matched(diff~, ..)] else {
    fail("expected one matched fragment")
  }
  let row_count = diff.rows.length()
  let row_copy = diff.rows.to_owned()
  row_copy.clear()
  guard changed.document() is TopLevel(final_top) else {
    fail("expected a stable top-level document")
  }
  guard final_top.sections is [Matched(diff=final_diff, ..)] else {
    fail("expected one stable fragment")
  }
  assert_eq(final_diff.rows.length(), row_count)

  let parsed = @mbtdiff.diff("fn broken( {", "fn okay() {}")
  guard parsed.document() is Whole({ fallbacks: [ParseError(sides~, ..)], .. }) else {
    fail("expected parse-error sides")
  }
  let side_copy = sides.to_owned()
  side_copy.clear()
  guard parsed.document()
    is Whole({ fallbacks: [ParseError(sides=later_sides, ..)], .. }) else {
    fail("expected stable parse-error sides")
  }
  assert_true(later_sides is [Old])
}

///|
test "external consumer observes pure reorder without flattening" {
  let result = @mbtdiff.diff(
    "fn first() {}\nfn second() {}", "fn second() {}\nfn first() {}",
  )
  assert_eq(status_name(result.status()), "reordered")
  guard result.document() is TopLevel(top) else {
    fail("expected a top-level reorder")
  }
  assert_true(top.reordered)
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [1, 0])
  for section in top.sections {
    assert_true(fragment_of_section(section).rows.is_empty())
  }
}
