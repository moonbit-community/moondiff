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
fn traverse_hunk_document(document : @mbtdiff.HunkDocument) -> Int {
  let _ : ArrayView[@mbtdiff.DiffHunk] = document.hunks
  let mut segments = 0
  for hunk in document.hunks {
    let _ : @mbtdiff.DiffHunk = hunk
    let _ : ArrayView[@mbtdiff.DiffBlock] = hunk.blocks
    let _ = (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len)
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) => {
          let _ : ArrayView[@mbtdiff.ContextLine] = lines
          for line in lines {
            let _ = (line.old_index, line.new_index, line.text)
          }
        }
        ChangeBlock(rows) | IgnoredBlock(rows) => {
          let _ : ArrayView[@mbtdiff.DiffRow] = rows
          for row in rows {
            let lines = match row {
              Paired(old_line, new_line) => [old_line, new_line]
              OldOnly(line) | NewOnly(line) => [line]
            }
            for line in lines {
              let _ : @mbtdiff.DiffLine = line
              let _ = (line.index, line.text())
              let _ : ArrayView[@mbtdiff.DiffSegment] = line.segments
              for segment in line.segments {
                let _ : @mbtdiff.DiffSegmentKind = segment.kind
                ignore(segment_name(segment.kind))
                segments += 1
              }
            }
          }
        }
      }
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
test "external consumer exhaustively matches the semantic result" {
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
  for section in top.sections {
    match section {
      Matched(old~, new~, old_context~, new_context~, diff~) => {
        let _ : @mbtdiff.LineRange = old
        let _ : @mbtdiff.LineRange = new
        let _ : String? = old_context
        let _ : String? = new_context
        let _ : @mbtdiff.DiffFragment = diff
        matched += 1
      }
      Deleted(old~, old_context~, diff~) => {
        let _ = (old.start, old.len, old_context, diff.fallbacks)
        deleted += 1
      }
      Inserted(new~, new_context~, diff~) => {
        let _ = (new.start, new.len, new_context, diff.fallbacks)
        inserted += 1
      }
    }
    ignore(traverse_hunk_document(fragment_of_section(section).document))
  }
  assert_eq((matched, deleted, inserted), (1, 1, 1))
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
    is Whole(
      { document: parsed_document, fallbacks: [ParseError(sides~, detail~)], }
    ) else {
    fail("expected one Whole parse fallback")
  }
  assert_false(parsed_document.hunks.is_empty())
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
  let hunk_count = diff.document.hunks.length()
  let hunk_copy = diff.document.hunks.to_owned()
  hunk_copy.clear()
  guard changed.document() is TopLevel(final_top) else {
    fail("expected a stable top-level document")
  }
  guard final_top.sections is [Matched(diff=final_diff, ..)] else {
    fail("expected one stable fragment")
  }
  assert_eq(final_diff.document.hunks.length(), hunk_count)

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
test "external consumer reads stable ignored test range views" {
  let result : @mbtdiff.DiffResult = @mbtdiff.diff(
    "fn production() {}",
    "fn production() {}\n/// test docs\ntest \"sample\" { inspect(1) }",
    options=@mbtdiff.DiffOptions(ignore_tests=true),
  )
  let old_ranges : ArrayView[@mbtdiff.LineRange] = result.ignored_test_ranges(
    Old,
  )
  let new_ranges : ArrayView[@mbtdiff.LineRange] = result.ignored_test_ranges(
    New,
  )
  assert_true(old_ranges.is_empty())
  assert_true(new_ranges is [{ start: 1, len: 2, }])

  let copy = new_ranges.to_owned()
  copy.clear()
  let later : ArrayView[@mbtdiff.LineRange] = result.ignored_test_ranges(New)
  assert_true(later is [{ start: 1, len: 2, }])
}

///|
test "renderers consume an explicit fragment HunkDocument" {
  let result = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  guard result.document() is TopLevel({ sections: [Matched(diff~, ..)], .. }) else {
    fail("expected one matched fragment")
  }
  let note : @render_html.HunkNote = {
    title: "Changed <function>",
    body: "Rendered & reviewed.",
  }
  let notes : Array[@render_html.HunkNote?] = [Some(note)]
  let split = @render_html.render_side_by_side(
    diff.document,
    line_numbers=true,
    hunk_notes=notes,
  )
  let unified_html = @render_html.render_unified(
    diff.document,
    line_numbers=true,
    hunk_notes=notes,
  )
  assert_true(split.contains("Changed &lt;function&gt;"), msg=split)
  assert_true(
    unified_html.contains("Rendered &amp; reviewed."),
    msg=unified_html,
  )

  let patch_hunks = @unified.render_unified_hunks(diff.document)
  assert_eq(patch_hunks.length(), 1)
  assert_true(patch_hunks[0].contains("-fn f() { 1 }"), msg=patch_hunks[0])
  assert_true(patch_hunks[0].contains("+fn f() { 2 }"), msg=patch_hunks[0])

  let options = @terminal.RenderOptions::new(
    use_color=false,
    old_max_line=10,
    new_max_line=10,
  )
  assert_true(options.old_max_line is Some(10))
  assert_true(options.new_max_line is Some(10))
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
    assert_true(fragment_of_section(section).document.hunks.is_empty())
  }
}
