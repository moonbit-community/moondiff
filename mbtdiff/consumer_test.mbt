///|
fn status_name(status : @mbtdiff.DiffStatus) -> String {
  match status {
    Identical => "identical"
    Changed => "changed"
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
    TopLevelReordering => "top-level-reordering"
  }
}

///|
fn scope_length(scope : @mbtdiff.FallbackScope) -> Int {
  match scope {
    WholeFile => 0
    Region(old~, new~) => {
      let old_len = old.map(range => range.start + range.len).unwrap_or(0)
      let new_len = new.map(range => range.start + range.len).unwrap_or(0)
      old_len + new_len
    }
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
test "consumer traverses and matches every public renderer-free IR type" {
  let _ : @mbtdiff.DiffMode = @mbtdiff.DiffMode::Ast
  assert_eq(
    fallback_name(SyntaxPositionsOutOfBounds(sides=[Old, New])),
    "syntax:old,new",
  )
  let result = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  let _ : @mbtdiff.DiffStatus = result.status()
  assert_eq(status_name(result.status()), "changed")
  let document : @mbtdiff.DiffDocument = result.document()
  let _ : ArrayView[@mbtdiff.DiffHunk] = document.hunks
  for hunk in document.hunks {
    let _ : @mbtdiff.DiffHunk = hunk
    let _ : ArrayView[@mbtdiff.DiffBlock] = hunk.blocks
    let _ = (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len)
    for block in hunk.blocks {
      let _ : @mbtdiff.DiffBlock = block
      match block {
        ContextBlock(lines) => {
          let _ : ArrayView[@mbtdiff.ContextLine] = lines
          for line in lines {
            let _ : @mbtdiff.ContextLine = line
            let _ = (line.old_index, line.new_index, line.text)
          }
        }
        ChangeBlock(rows) | IgnoredBlock(rows) => {
          let _ : ArrayView[@mbtdiff.DiffRow] = rows
          for row in rows {
            let _ : @mbtdiff.DiffRow = row
            match row {
              Paired(old_line, new_line) => {
                let _ : @mbtdiff.DiffLine = old_line
                let _ : @mbtdiff.DiffLine = new_line
                let _ = (old_line.text(), new_line.text())
              }
              OldOnly(line) | NewOnly(line) => {
                let _ = line.text()
                let _ : ArrayView[@mbtdiff.DiffSegment] = line.segments
                for segment in line.segments {
                  let _ : @mbtdiff.DiffSegment = segment
                  let _ : @mbtdiff.DiffSegmentKind = segment.kind
                  let _ = (segment_name(segment.kind), segment.text)
                }
              }
            }
          }
        }
      }
    }
  }
  let rebased : @mbtdiff.DiffDocument = document.rebase(0, 0)
  assert_true(rebased == document)
  let fallback_view : ArrayView[@mbtdiff.FallbackInfo] = result.fallbacks()
  for fallback in fallback_view {
    let _ : @mbtdiff.FallbackInfo = fallback
    let _ : @mbtdiff.FallbackReason = fallback.reason
    let _ : @mbtdiff.FallbackScope = fallback.scope
    let _ = (fallback_name(fallback.reason), scope_length(fallback.scope))
  }

  let parse = @mbtdiff.diff("fn broken( {", "fn okay() {}")
  assert_false(parse.fallbacks().is_empty())
  assert_false(fallback_name(parse.fallbacks()[0].reason).is_empty())
  guard parse.fallbacks()[0].reason is ParseError(sides~, ..) else {
    fail("expected a parse fallback")
  }
  let _ : ArrayView[@mbtdiff.DiffSide] = sides
}

///|
test "owned copies of result views cannot mutate later accessor results" {
  let changed = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  let document = changed.document()
  guard document.hunks is [hunk] else { fail("expected one changed hunk") }
  let hunk_count = document.hunks.length()
  let hunk_copy = document.hunks.to_owned()
  hunk_copy.clear()
  assert_eq(changed.document().hunks.length(), hunk_count)

  let block_count = hunk.blocks.length()
  let block_copy = hunk.blocks.to_owned()
  block_copy.clear()
  assert_eq(changed.document().hunks[0].blocks.length(), block_count)

  let mut selected_line : @mbtdiff.DiffLine? = None
  let mut row_count = 0
  for block in hunk.blocks {
    guard block is ChangeBlock(rows) else { continue }
    if row_count == 0 {
      row_count = rows.length()
    }
    if selected_line is None && rows is [row, ..] {
      selected_line = Some(
        match row {
          Paired(old_line, _) => old_line
          OldOnly(line) | NewOnly(line) => line
        },
      )
    }
    let row_copy = rows.to_owned()
    row_copy.clear()
  }
  guard selected_line is Some(line) else { fail("expected one changed line") }
  let original_text = line.text()
  let segment_copy = line.segments.to_owned()
  segment_copy.clear()
  assert_eq(line.text(), original_text)
  guard changed.document().hunks[0].blocks is [ChangeBlock(rows), ..] else {
    fail("expected the original change block")
  }
  assert_eq(rows.length(), row_count)

  let parsed = @mbtdiff.diff("fn broken( {", "fn okay() {}")
  let fallback_copy = parsed.fallbacks().to_owned()
  fallback_copy.clear()
  assert_eq(parsed.fallbacks().length(), 1)
  guard parsed.fallbacks()[0].reason is ParseError(sides~, ..) else {
    fail("expected parse-error sides")
  }
  let side_copy = sides.to_owned()
  side_copy.clear()
  guard parsed.fallbacks()[0].reason is ParseError(sides=later_sides, ..) else {
    fail("expected stable parse-error sides")
  }
  assert_true(later_sides is [Old])
}

///|
test "consumer renders DiffResult documents with the experimental public packages" {
  let document = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }").document()
  let note : @render_html.HunkNote = {
    title: "Changed <function>",
    body: "Rendered & reviewed.",
  }
  let notes : Array[@render_html.HunkNote?] = [Some(note)]
  let split = @render_html.render_side_by_side(
    document,
    line_numbers=true,
    hunk_notes=notes,
  )
  let unified_html = @render_html.render_unified(
    document,
    line_numbers=true,
    hunk_notes=notes,
  )
  assert_true(split.contains("Changed &lt;function&gt;"), msg=split)
  assert_true(
    unified_html.contains("Rendered &amp; reviewed."),
    msg=unified_html,
  )
  assert_eq(
    @render_html.render_side_by_side_hunks(
      document,
      line_numbers=true,
      hunk_notes=notes,
    ),
    [split],
  )
  assert_eq(
    @render_html.render_unified_hunks(
      document,
      line_numbers=true,
      hunk_notes=notes,
    ),
    [unified_html],
  )

  let patch_hunks = @unified.render_unified_hunks(document)
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
  let terminal_text = @terminal.render_document(
    "old.mbt",
    "new.mbt",
    document,
    options~,
  )
  assert_true(terminal_text.contains("--- old.mbt\n+++ new.mbt\n"))
  assert_false(terminal_text.contains("\u{1b}["))
}
