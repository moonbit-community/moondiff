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
    GraphLimitExceeded(limit~) => "graph:\{limit}"
    ComputationLimitExceeded(stage~, limit~) => "\{stage_name(stage)}:\{limit}"
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
  let result = @mbtdiff.diff("fn f() { 1 }", "fn f() { 2 }")
  let _ : @mbtdiff.DiffStatus = result.status()
  assert_eq(status_name(result.status()), "changed")
  let document : @mbtdiff.DiffDocument = result.document()
  for hunk in document.hunks {
    let _ : @mbtdiff.DiffHunk = hunk
    let _ = (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len)
    for block in hunk.blocks {
      let _ : @mbtdiff.DiffBlock = block
      match block {
        ContextBlock(lines) =>
          for line in lines {
            let _ : @mbtdiff.ContextLine = line
            let _ = (line.old_index, line.new_index, line.text)
          }
        ChangeBlock(rows) | IgnoredBlock(rows) =>
          for row in rows {
            let _ : @mbtdiff.DiffRow = row
            match row {
              Paired(old_line, new_line) => {
                let _ : @mbtdiff.DiffLine = old_line
                let _ : @mbtdiff.DiffLine = new_line
              }
              OldOnly(line) | NewOnly(line) =>
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
  for fallback in result.fallbacks() {
    let _ : @mbtdiff.FallbackInfo = fallback
    let _ : @mbtdiff.FallbackReason = fallback.reason
    let _ : @mbtdiff.FallbackScope = fallback.scope
    let _ = (fallback_name(fallback.reason), scope_length(fallback.scope))
  }

  let parse = @mbtdiff.diff("fn broken( {", "fn okay() {}")
  assert_true(parse.has_fallback())
  assert_false(fallback_name(parse.fallbacks()[0].reason).is_empty())
}
