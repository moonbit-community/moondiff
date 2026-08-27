///|
// Comment filtering always removes a suffix (possibly the whole line), so the
// retained view is also the exact prefix length in UTF-16 code units.
fn comment_ignored_suffix(line : SourceLineView) -> String {
  line.source.view(start_offset=line.visible.length()).to_owned()
}

///|
fn ignored_comment_line(index : Int, line : SourceLineView) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = []
  push_segment(segments, Unchanged, line.visible)
  push_segment(segments, Ignored, comment_ignored_suffix(line))
  { index, segments: segments[:] }
}

///|
// Retain calculated code segments while replacing the excluded source suffix
// with one renderer-neutral segment. Structural documents still contain the
// original comment text, so truncate them at the visible code boundary.
fn neutralize_comment_suffix(
  line : @model.DiffLine,
  view : SourceLineView,
) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = []
  let code_len = view.visible.length()
  let mut consumed = 0
  for segment in line.segments {
    if consumed >= code_len {
      break
    }
    let remaining = code_len - consumed
    let take = @cmp.minimum(segment.text.length(), remaining)
    push_segment(
      segments,
      segment.kind,
      if take == segment.text.length() {
        segment.text
      } else {
        segment.text.view(end_offset=take).to_owned()
      },
    )
    consumed += take
  }
  if consumed < code_len {
    push_segment(
      segments,
      Unchanged,
      view.visible.view(start_offset=consumed).to_owned(),
    )
  }
  push_segment(segments, Ignored, comment_ignored_suffix(view))
  { index: line.index, segments: segments[:] }
}

///|
fn filter_comment_row(
  row : @model.DiffRow,
  old_lines : ArrayView[SourceLineView],
  new_lines : ArrayView[SourceLineView],
) -> (@model.DiffRow, Bool) {
  match row {
    Paired(old_line, new_line) => {
      let old_view = old_lines[old_line.index]
      let new_view = new_lines[new_line.index]
      if old_view.visible == new_view.visible {
        (
          Paired(
            ignored_comment_line(old_line.index, old_view),
            ignored_comment_line(new_line.index, new_view),
          ),
          true,
        )
      } else {
        (
          Paired(
            neutralize_comment_suffix(old_line, old_view),
            neutralize_comment_suffix(new_line, new_view),
          ),
          false,
        )
      }
    }
    OldOnly(line) => {
      let view = old_lines[line.index]
      if view.fully_ignored() {
        (OldOnly(ignored_comment_line(line.index, view)), true)
      } else {
        (OldOnly(neutralize_comment_suffix(line, view)), false)
      }
    }
    NewOnly(line) => {
      let view = new_lines[line.index]
      if view.fully_ignored() {
        (NewOnly(ignored_comment_line(line.index, view)), true)
      } else {
        (NewOnly(neutralize_comment_suffix(line, view)), false)
      }
    }
  }
}

///|
fn append_comment_rows(
  blocks : Array[@model.DiffBlock],
  rows : ArrayView[@model.DiffRow],
  old_lines : ArrayView[SourceLineView],
  new_lines : ArrayView[SourceLineView],
) -> Bool {
  let changes : Array[@model.DiffRow] = []
  let ignored : Array[@model.DiffRow] = []
  let mut has_change = false
  for row in rows {
    let (filtered, is_ignored) = filter_comment_row(row, old_lines, new_lines)
    if is_ignored {
      if !changes.is_empty() {
        blocks.push(ChangeBlock(changes.copy()[:]))
        changes.clear()
      }
      ignored.push(filtered)
    } else {
      has_change = true
      if !ignored.is_empty() {
        blocks.push(IgnoredBlock(ignored.copy()[:]))
        ignored.clear()
      }
      changes.push(filtered)
    }
  }
  if !changes.is_empty() {
    blocks.push(ChangeBlock(changes[:]))
  }
  if !ignored.is_empty() {
    blocks.push(IgnoredBlock(ignored[:]))
  }
  has_change
}

///|
/// Apply comment and blank-line filtering to an already aligned document.
/// This preserves the document's row pairing, which is important for AST
/// alignment, while sharing the same lexer-backed filtering policy as lexical
/// view. Hunks containing no remaining semantic changes are removed.
pub fn ignore_comments(
  document : @model.HunkDocument,
  old~ : ArrayView[String],
  new~ : ArrayView[String],
) -> @model.HunkDocument {
  let old_view = SourceView::from_lines(old, ignore_comments=true)
  let new_view = SourceView::from_lines(new, ignore_comments=true)
  let hunks : Array[@model.DiffHunk] = []
  for hunk in document.hunks {
    let blocks : Array[@model.DiffBlock] = []
    let mut has_change = false
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) => blocks.push(ContextBlock(lines))
        ChangeBlock(rows) =>
          if append_comment_rows(
              blocks,
              rows,
              old_view.line_views,
              new_view.line_views,
            ) {
            has_change = true
          }
        IgnoredBlock(rows) => blocks.push(IgnoredBlock(rows))
      }
    }
    if has_change {
      hunks.push({ ..hunk, blocks: blocks[:] })
    }
  }
  { hunks: hunks[:] }
}
