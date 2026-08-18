///|
/// Whether one source segment is unchanged or belongs to an intraline change.
/// Renderers decide how to present `Changed`; the calculation layer never
/// assigns markup, colors, or terminal styles.
pub(all) enum DiffSegmentKind {
  Unchanged
  Changed
  /// Source text excluded from comparison but retained for faithful display.
  Ignored
} derive(Eq)

///|
/// One exact source-text segment in a changed line. Concatenating a line's
/// segment texts always reconstructs that source line byte-for-byte.
pub(all) struct DiffSegment {
  kind : DiffSegmentKind
  text : String
} derive(Eq)

///|
/// One changed source line. `index` is zero-based in its original input.
pub(all) struct DiffLine {
  index : Int
  segments : Array[DiffSegment]
} derive(Eq)

///|
/// Reconstruct the exact source text of this line.
pub fn DiffLine::text(self : DiffLine) -> String {
  let buf = StringBuilder::new()
  for segment in self.segments {
    buf <+ "\{segment.text}"
  }
  buf.to_string()
}

///|
/// One unchanged line shared by both inputs. Indices are zero-based.
pub(all) struct ContextLine {
  old_index : Int
  new_index : Int
  text : String
} derive(Eq)

///|
/// One aligned row in a change block. The enum keeps a present blank line
/// distinct from a missing side without relying on empty-string sentinels.
pub(all) enum DiffRow {
  Paired(DiffLine, DiffLine)
  OldOnly(DiffLine)
  NewOnly(DiffLine)
} derive(Eq)

///|
/// One ordered block inside a hunk. Change-block boundaries are retained so a
/// unified renderer can emit all deletions before all insertions while a split
/// renderer consumes the aligned rows directly.
pub(all) enum DiffBlock {
  ContextBlock(Array[ContextLine])
  ChangeBlock(Array[DiffRow])
  /// Rows whose source text differs only in content excluded from comparison.
  /// Renderers keep their original text and line numbers without presenting
  /// them as additions or deletions.
  IgnoredBlock(Array[DiffRow])
} derive(Eq)

///|
/// One grouped diff hunk. Starts are zero-based cursors and lengths are source
/// line counts. Renderers derive display headers from these numeric ranges.
pub(all) struct DiffHunk {
  old_start : Int
  old_len : Int
  new_start : Int
  new_len : Int
  blocks : Array[DiffBlock]
} derive(Eq)

///|
/// A fully calculated, renderer-neutral diff document.
pub(all) struct DiffDocument {
  hunks : Array[DiffHunk]
} derive(Eq)

///|
fn DiffLine::rebase_index(self : DiffLine, offset : Int) -> DiffLine {
  { index: self.index + offset, segments: self.segments.copy() }
}

///|
fn DiffBlock::rebase_indexes(
  self : DiffBlock,
  old_line_offset : Int,
  new_line_offset : Int,
) -> DiffBlock {
  match self {
    ContextBlock(lines) => {
      let rebased : Array[ContextLine] = []
      for line in lines {
        rebased.push({
          old_index: line.old_index + old_line_offset,
          new_index: line.new_index + new_line_offset,
          text: line.text,
        })
      }
      ContextBlock(rebased)
    }
    ChangeBlock(rows) | IgnoredBlock(rows) => {
      let rebased : Array[DiffRow] = []
      for row in rows {
        rebased.push(
          match row {
            Paired(old_line, new_line) =>
              Paired(
                old_line.rebase_index(old_line_offset),
                new_line.rebase_index(new_line_offset),
              )
            OldOnly(line) => OldOnly(line.rebase_index(old_line_offset))
            NewOnly(line) => NewOnly(line.rebase_index(new_line_offset))
          },
        )
      }
      if self is ChangeBlock(_) {
        ChangeBlock(rebased)
      } else {
        IgnoredBlock(rebased)
      }
    }
  }
}

///|
/// Return a new document whose zero-based source indexes are shifted by the
/// supplied offsets. Hunk ranges, context indexes, and changed-line indexes
/// are rebased together.
pub fn DiffDocument::rebase(
  self : DiffDocument,
  old_line_offset : Int,
  new_line_offset : Int,
) -> DiffDocument {
  let hunks : Array[DiffHunk] = []
  for hunk in self.hunks {
    let old_start = hunk.old_start + old_line_offset
    let new_start = hunk.new_start + new_line_offset
    let blocks : Array[DiffBlock] = []
    for block in hunk.blocks {
      blocks.push(block.rebase_indexes(old_line_offset, new_line_offset))
    }
    hunks.push({
      old_start,
      old_len: hunk.old_len,
      new_start,
      new_len: hunk.new_len,
      blocks,
    })
  }
  { hunks, }
}

///|
fn push_diff_segment(
  segments : Array[DiffSegment],
  kind : DiffSegmentKind,
  text : String,
) -> Unit {
  if text == "" {
    return
  }
  let last = segments.length() - 1
  if last >= 0 && segments[last].kind == kind {
    let previous = segments[last]
    segments[last] = { kind, text: previous.text + text }
  } else {
    segments.push({ kind, text })
  }
}

///|
fn push_token_range(
  segments : Array[DiffSegment],
  tokens : ArrayView[Tok],
  start : Int,
  end : Int,
  kind : DiffSegmentKind,
) -> Unit {
  let buf = StringBuilder::new()
  for index in start..<end {
    buf <+ "\{tokens[index].text}"
  }
  push_diff_segment(segments, kind, buf.to_string())
}

///|
fn diff_token_text_is_whitespace(token : Tok) -> Bool {
  if token.text == "" {
    return false
  }
  for char in token.text {
    if !char.is_whitespace() {
      return false
    }
  }
  true
}

///|
/// Append one changed token run while leaving leading and trailing whitespace
/// unchanged. Internal whitespace remains part of the changed segment.
fn flush_changed_tokens(
  segments : Array[DiffSegment],
  run : Array[Tok],
) -> Unit {
  let mut semantic_start = 0
  while semantic_start < run.length() &&
        diff_token_text_is_whitespace(run[semantic_start]) {
    semantic_start += 1
  }
  if semantic_start == run.length() {
    push_token_range(segments, run, 0, run.length(), Unchanged)
  } else {
    let mut semantic_end = run.length()
    while semantic_end > semantic_start &&
          diff_token_text_is_whitespace(run[semantic_end - 1]) {
      semantic_end -= 1
    }
    push_token_range(segments, run, 0, semantic_start, Unchanged)
    push_token_range(segments, run, semantic_start, semantic_end, Changed)
    push_token_range(segments, run, semantic_end, run.length(), Unchanged)
  }
  run.clear()
}

///|
fn plain_segments(text : String) -> Array[DiffSegment] {
  if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
}

///|
fn full_line_segments(tokens : ArrayView[Tok]) -> Array[DiffSegment] {
  let segments : Array[DiffSegment] = []
  let run = tokens.to_owned()
  flush_changed_tokens(segments, run)
  segments
}

///|
fn pair_row_segments(
  ops : ArrayView[Op],
) -> (Array[DiffSegment], Array[DiffSegment]) {
  let old_segments : Array[DiffSegment] = []
  let new_segments : Array[DiffSegment] = []
  let old_run : Array[Tok] = []
  let new_run : Array[Tok] = []
  for op in ops {
    match op {
      OEq(token) => {
        flush_changed_tokens(old_segments, old_run)
        flush_changed_tokens(new_segments, new_run)
        push_diff_segment(old_segments, Unchanged, token.text)
        push_diff_segment(new_segments, Unchanged, token.text)
      }
      OSub(old_token, new_token) => {
        old_run.push(old_token)
        new_run.push(new_token)
      }
      ODel(token) => old_run.push(token)
      OIns(token) => new_run.push(token)
    }
  }
  flush_changed_tokens(old_segments, old_run)
  flush_changed_tokens(new_segments, new_run)
  (old_segments, new_segments)
}

///|
fn projected_line_segments(
  tokens : ArrayView[Tok],
  changed : ArrayView[Bool],
) -> Array[DiffSegment] {
  let segments : Array[DiffSegment] = []
  let run : Array[Tok] = []
  for index, token in tokens {
    if changed[index] {
      run.push(token)
    } else if token.kind is Space && run.length() > 0 {
      let mut next = index + 1
      while next < tokens.length() && tokens[next].kind is Space {
        next += 1
      }
      if next < tokens.length() && changed[next] {
        run.push(token)
      } else {
        flush_changed_tokens(segments, run)
        push_diff_segment(segments, Unchanged, token.text)
      }
    } else {
      flush_changed_tokens(segments, run)
      push_diff_segment(segments, Unchanged, token.text)
    }
  }
  flush_changed_tokens(segments, run)
  segments
}

///|
fn make_diff_line(index : Int, segments : Array[DiffSegment]) -> DiffLine {
  { index, segments }
}

///|
fn make_plain_diff_line(index : Int, text : String) -> DiffLine {
  { index, segments: plain_segments(text) }
}

///|
/// Calculate semantic row pairing and intraline segments for one replacement
/// block. This is the renderer-neutral counterpart of the former HTML
/// `prepare_replacement` helper.
fn semantic_change_rows(
  old_lines : ArrayView[ComparableLine],
  new_lines : ArrayView[ComparableLine],
  old_start : Int,
  new_start : Int,
) -> Array[DiffRow] {
  let rows : Array[DiffRow] = []
  if alignment_tokens(old_lines, new_lines, line => line.text) is Some(tokens) {
    let changes = window_changes(tokens.olds, tokens.news)
    for pair in align(tokens.olds, tokens.news) {
      match pair {
        (Some(old_index), Some(new_index)) => {
          let (old_segments, new_segments) = if changes is Some(window) {
            (
              projected_line_segments(
                tokens.olds[old_index],
                window.old_changed[old_index],
              ),
              projected_line_segments(
                tokens.news[new_index],
                window.new_changed[new_index],
              ),
            )
          } else if !traceback_cells_within_limit(
              tokens.olds[old_index].length(),
              tokens.news[new_index].length(),
            ) {
            (
              plain_segments(old_lines[old_index].text),
              plain_segments(new_lines[new_index].text),
            )
          } else {
            pair_row_segments(
              pair_ops(tokens.olds[old_index], tokens.news[new_index]),
            )
          }
          rows.push(
            Paired(
              make_diff_line(old_start + old_index, old_segments),
              make_diff_line(new_start + new_index, new_segments),
            ),
          )
        }
        (Some(old_index), None) => {
          let segments = if changes is Some(window) {
            projected_line_segments(
              tokens.olds[old_index],
              window.old_changed[old_index],
            )
          } else {
            full_line_segments(tokens.olds[old_index])
          }
          rows.push(OldOnly(make_diff_line(old_start + old_index, segments)))
        }
        (None, Some(new_index)) => {
          let segments = if changes is Some(window) {
            projected_line_segments(
              tokens.news[new_index],
              window.new_changed[new_index],
            )
          } else {
            full_line_segments(tokens.news[new_index])
          }
          rows.push(NewOnly(make_diff_line(new_start + new_index, segments)))
        }
        (None, None) => ()
      }
    }
  } else {
    for offset, line in old_lines {
      rows.push(OldOnly(make_plain_diff_line(old_start + offset, line.text)))
    }
    for offset, line in new_lines {
      rows.push(NewOnly(make_plain_diff_line(new_start + offset, line.text)))
    }
  }
  rows
}

///|
fn plain_change_rows(
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_start : Int,
  new_start : Int,
) -> Array[DiffRow] {
  let rows : Array[DiffRow] = []
  let row_count = if old_lines.length() > new_lines.length() {
    old_lines.length()
  } else {
    new_lines.length()
  }
  for offset in 0..<row_count {
    match (old_lines.get(offset), new_lines.get(offset)) {
      (Some(old_line), Some(new_line)) =>
        rows.push(
          Paired(
            make_plain_diff_line(old_start + offset, old_line),
            make_plain_diff_line(new_start + offset, new_line),
          ),
        )
      (Some(old_line), None) =>
        rows.push(OldOnly(make_plain_diff_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(make_plain_diff_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  rows
}

///|
fn hunk_range(edits : ArrayView[@diff.Edit]) -> (Int, Int, Int, Int) {
  let (old_start, new_start, _, _) = edit_bounds(edits[0])
  let (_, _, old_end, new_end) = edit_bounds(edits[edits.length() - 1])
  (old_start, old_end - old_start, new_start, new_end - new_start)
}

///|
fn semantic_hunk(hunk : @diff.Hunk[ComparableLine]) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Delete(old_index~, old_len~, ..) if index + 1 < edits.length() &&
        edits[index + 1] is Insert(..) => {
        guard! edits[index + 1] is Insert(new_index~, new_len~, ..)
        blocks.push(
          ChangeBlock(
            semantic_change_rows(
              old_view.view(start=old_index, end=old_index + old_len),
              new_view.view(start=new_index, end=new_index + new_len),
              old_index,
              new_index,
            ),
          ),
        )
        index += 2
      }
      Equal(old_index~, new_index~, len~) => {
        let lines : Array[ContextLine] = []
        for offset in 0..<len {
          lines.push({
            old_index: old_index + offset,
            new_index: new_index + offset,
            text: old_view[old_index + offset].text,
          })
        }
        blocks.push(ContextBlock(lines))
        index += 1
      }
      Delete(old_index~, old_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<old_len {
          let line = old_view[old_index + offset]
          rows.push(
            OldOnly(make_plain_diff_line(old_index + offset, line.text)),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
      Insert(new_index~, new_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<new_len {
          let line = new_view[new_index + offset]
          rows.push(
            NewOnly(make_plain_diff_line(new_index + offset, line.text)),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { old_start, old_len, new_start, new_len, blocks }
}

///|
fn plain_hunk(hunk : @diff.Hunk[String]) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Delete(old_index~, old_len~, ..) if index + 1 < edits.length() &&
        edits[index + 1] is Insert(..) => {
        guard! edits[index + 1] is Insert(new_index~, new_len~, ..)
        blocks.push(
          ChangeBlock(
            plain_change_rows(
              old_view.view(start=old_index, end=old_index + old_len),
              new_view.view(start=new_index, end=new_index + new_len),
              old_index,
              new_index,
            ),
          ),
        )
        index += 2
      }
      Equal(old_index~, new_index~, len~) => {
        let lines : Array[ContextLine] = []
        for offset in 0..<len {
          lines.push({
            old_index: old_index + offset,
            new_index: new_index + offset,
            text: old_view[old_index + offset],
          })
        }
        blocks.push(ContextBlock(lines))
        index += 1
      }
      Delete(old_index~, old_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<old_len {
          rows.push(
            OldOnly(
              make_plain_diff_line(
                old_index + offset,
                old_view[old_index + offset],
              ),
            ),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
      Insert(new_index~, new_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<new_len {
          rows.push(
            NewOnly(
              make_plain_diff_line(
                new_index + offset,
                new_view[new_index + offset],
              ),
            ),
          )
        }
        blocks.push(ChangeBlock(rows))
        index += 1
      }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { old_start, old_len, new_start, new_len, blocks }
}

///|
fn comment_projections(lines : ArrayView[String]) -> Array[CommentProjection] {
  lines.map(project_comments)
}

///|
priv struct ProjectedSourceLine {
  projection : CommentProjection
  source_index : Int
}

///|
fn significant_projected_lines(
  lines : ArrayView[CommentProjection],
) -> Array[ProjectedSourceLine] {
  let projected : Array[ProjectedSourceLine] = []
  for source_index, projection in lines {
    if !projection.ignored_only {
      projected.push({ projection, source_index })
    }
  }
  projected
}

///|
fn projected_code_lines(
  lines : ArrayView[ProjectedSourceLine],
) -> Array[String] {
  lines.map(line => line.projection.code)
}

///|
fn projection_text(line : CommentProjection) -> String {
  line.code + line.ignored_suffix
}

///|
fn ignored_diff_line(index : Int, line : CommentProjection) -> DiffLine {
  let segments : Array[DiffSegment] = []
  push_diff_segment(segments, Unchanged, line.code)
  push_diff_segment(segments, Ignored, line.ignored_suffix)
  { index, segments }
}

///|
// Retain calculated code segments while replacing excluded source text with a
// renderer-neutral `Ignored` segment. This also works for AST lines whose
// original segments still covered a comment or whitespace-only line:
// everything after `code` is deliberately discarded and re-appended once.
fn neutralize_comment_suffix(
  line : DiffLine,
  projection : CommentProjection,
) -> DiffLine {
  let segments : Array[DiffSegment] = []
  let code_len = projection.code.length()
  let mut consumed = 0
  for segment in line.segments {
    if consumed >= code_len {
      break
    }
    let remaining = code_len - consumed
    let take = if segment.text.length() < remaining {
      segment.text.length()
    } else {
      remaining
    }
    push_diff_segment(
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
    push_diff_segment(
      segments,
      Unchanged,
      projection.code.view(start_offset=consumed).to_owned(),
    )
  }
  push_diff_segment(segments, Ignored, projection.ignored_suffix)
  { index: line.index, segments }
}

///|
// Return the source-faithful row and whether it is excluded from comparison as
// a comment-only or whitespace-only change.
fn project_comment_row(
  row : DiffRow,
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
) -> (DiffRow, Bool) {
  match row {
    Paired(old_line, new_line) => {
      let old_projection = old_lines[old_line.index]
      let new_projection = new_lines[new_line.index]
      if old_projection.code == new_projection.code {
        (
          Paired(
            ignored_diff_line(old_line.index, old_projection),
            ignored_diff_line(new_line.index, new_projection),
          ),
          true,
        )
      } else {
        (
          Paired(
            neutralize_comment_suffix(old_line, old_projection),
            neutralize_comment_suffix(new_line, new_projection),
          ),
          false,
        )
      }
    }
    OldOnly(line) => {
      let projection = old_lines[line.index]
      if projection.ignored_only {
        (OldOnly(ignored_diff_line(line.index, projection)), true)
      } else {
        (OldOnly(neutralize_comment_suffix(line, projection)), false)
      }
    }
    NewOnly(line) => {
      let projection = new_lines[line.index]
      if projection.ignored_only {
        (NewOnly(ignored_diff_line(line.index, projection)), true)
      } else {
        (NewOnly(neutralize_comment_suffix(line, projection)), false)
      }
    }
  }
}

///|
fn append_projected_rows(
  blocks : Array[DiffBlock],
  rows : ArrayView[DiffRow],
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
) -> Bool {
  let changes : Array[DiffRow] = []
  let ignored : Array[DiffRow] = []
  let mut has_change = false
  for row in rows {
    let (projected, is_ignored) = project_comment_row(row, old_lines, new_lines)
    if is_ignored {
      if !changes.is_empty() {
        blocks.push(ChangeBlock(changes.copy()))
        changes.clear()
      }
      ignored.push(projected)
    } else {
      has_change = true
      if !ignored.is_empty() {
        blocks.push(IgnoredBlock(ignored.copy()))
        ignored.clear()
      }
      changes.push(projected)
    }
  }
  if !changes.is_empty() {
    blocks.push(ChangeBlock(changes))
  }
  if !ignored.is_empty() {
    blocks.push(IgnoredBlock(ignored))
  }
  has_change
}

///|
fn projected_source_cursor(
  lines : ArrayView[ProjectedSourceLine],
  index : Int,
  source_length : Int,
) -> Int {
  if index < lines.length() {
    lines[index].source_index
  } else {
    source_length
  }
}

///|
fn projected_hunk_start(
  lines : ArrayView[ProjectedSourceLine],
  index : Int,
) -> Int {
  if index == 0 {
    0
  } else {
    lines[index - 1].source_index + 1
  }
}

///|
fn append_ignored_source_gap(
  blocks : Array[DiffBlock],
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> Unit {
  let rows : Array[DiffRow] = []
  let old_len = old_end - old_start
  let new_len = new_end - new_start
  let row_count = if old_len > new_len { old_len } else { new_len }
  for offset in 0..<row_count {
    let old_line = if offset < old_len {
      old_lines.get(old_start + offset)
    } else {
      None
    }
    let new_line = if offset < new_len {
      new_lines.get(new_start + offset)
    } else {
      None
    }
    match (old_line, new_line) {
      (Some(old_line), Some(new_line)) =>
        rows.push(
          Paired(
            ignored_diff_line(old_start + offset, old_line),
            ignored_diff_line(new_start + offset, new_line),
          ),
        )
      (Some(old_line), None) =>
        rows.push(OldOnly(ignored_diff_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(ignored_diff_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  if !rows.is_empty() {
    blocks.push(IgnoredBlock(rows))
  }
}

///|
fn append_mapped_change_rows(
  blocks : Array[DiffBlock],
  rows : ArrayView[DiffRow],
  old_projected : ArrayView[ProjectedSourceLine],
  new_projected : ArrayView[ProjectedSourceLine],
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let mut old_cursor = old_cursor
  let mut new_cursor = new_cursor
  let changes : Array[DiffRow] = []
  for row in rows {
    let (old_target, new_target) = match row {
      Paired(old_line, new_line) =>
        (
          old_projected[old_line.index].source_index,
          new_projected[new_line.index].source_index,
        )
      OldOnly(old_line) =>
        (old_projected[old_line.index].source_index, new_cursor)
      NewOnly(new_line) =>
        (old_cursor, new_projected[new_line.index].source_index)
    }
    if old_cursor < old_target || new_cursor < new_target {
      if !changes.is_empty() {
        blocks.push(ChangeBlock(changes.copy()))
        changes.clear()
      }
      append_ignored_source_gap(
        blocks, old_lines, new_lines, old_cursor, old_target, new_cursor, new_target,
      )
    }
    changes.push(
      match row {
        Paired(old_line, new_line) => {
          let old_entry = old_projected[old_line.index]
          let new_entry = new_projected[new_line.index]
          old_cursor = old_entry.source_index + 1
          new_cursor = new_entry.source_index + 1
          Paired(
            neutralize_comment_suffix(
              { ..old_line, index: old_entry.source_index },
              old_entry.projection,
            ),
            neutralize_comment_suffix(
              { ..new_line, index: new_entry.source_index },
              new_entry.projection,
            ),
          )
        }
        OldOnly(old_line) => {
          let old_entry = old_projected[old_line.index]
          old_cursor = old_entry.source_index + 1
          OldOnly(
            neutralize_comment_suffix(
              { ..old_line, index: old_entry.source_index },
              old_entry.projection,
            ),
          )
        }
        NewOnly(new_line) => {
          let new_entry = new_projected[new_line.index]
          new_cursor = new_entry.source_index + 1
          NewOnly(
            neutralize_comment_suffix(
              { ..new_line, index: new_entry.source_index },
              new_entry.projection,
            ),
          )
        }
      },
    )
  }
  if !changes.is_empty() {
    blocks.push(ChangeBlock(changes))
  }
  (old_cursor, new_cursor)
}

///|
fn append_mapped_equal_lines(
  blocks : Array[DiffBlock],
  old_index : Int,
  new_index : Int,
  len : Int,
  old_projected : ArrayView[ProjectedSourceLine],
  new_projected : ArrayView[ProjectedSourceLine],
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let mut old_position = old_cursor
  let mut new_position = new_cursor
  let context : Array[ContextLine] = []
  for offset in 0..<len {
    let old_entry = old_projected[old_index + offset]
    let new_entry = new_projected[new_index + offset]
    if old_position < old_entry.source_index ||
      new_position < new_entry.source_index {
      if !context.is_empty() {
        blocks.push(ContextBlock(context.copy()))
        context.clear()
      }
      append_ignored_source_gap(
        blocks,
        old_lines,
        new_lines,
        old_position,
        old_entry.source_index,
        new_position,
        new_entry.source_index,
      )
    }
    let old_line = old_entry.projection
    let new_line = new_entry.projection
    if projection_text(old_line) == projection_text(new_line) {
      context.push({
        old_index: old_entry.source_index,
        new_index: new_entry.source_index,
        text: projection_text(old_line),
      })
    } else {
      if !context.is_empty() {
        blocks.push(ContextBlock(context.copy()))
        context.clear()
      }
      blocks.push(
        IgnoredBlock([
          Paired(
            ignored_diff_line(old_entry.source_index, old_line),
            ignored_diff_line(new_entry.source_index, new_line),
          ),
        ]),
      )
    }
    old_position = old_entry.source_index + 1
    new_position = new_entry.source_index + 1
  }
  if !context.is_empty() {
    blocks.push(ContextBlock(context))
  }
  (old_position, new_position)
}

///|
fn comment_hunk(
  hunk : @diff.Hunk[ComparableLine],
  old_projected : ArrayView[ProjectedSourceLine],
  new_projected : ArrayView[ProjectedSourceLine],
  old_lines : ArrayView[CommentProjection],
  new_lines : ArrayView[CommentProjection],
) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let (
    old_filtered_start,
    old_filtered_len,
    new_filtered_start,
    new_filtered_len,
  ) = hunk_range(edits)
  let old_start = projected_hunk_start(old_projected, old_filtered_start)
  let new_start = projected_hunk_start(new_projected, new_filtered_start)
  let old_end = projected_source_cursor(
    old_projected,
    old_filtered_start + old_filtered_len,
    old_lines.length(),
  )
  let new_end = projected_source_cursor(
    new_projected,
    new_filtered_start + new_filtered_len,
    new_lines.length(),
  )
  let mut old_cursor = old_start
  let mut new_cursor = new_start
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Delete(old_index~, old_len~, ..) if index + 1 < edits.length() &&
        edits[index + 1] is Insert(..) => {
        guard! edits[index + 1] is Insert(new_index~, new_len~, ..)
        let rows = semantic_change_rows(
          old_view.view(start=old_index, end=old_index + old_len),
          new_view.view(start=new_index, end=new_index + new_len),
          old_index,
          new_index,
        )
        let (next_old_cursor, next_new_cursor) = append_mapped_change_rows(
          blocks, rows, old_projected, new_projected, old_lines, new_lines, old_cursor,
          new_cursor,
        )
        old_cursor = next_old_cursor
        new_cursor = next_new_cursor
        index += 2
      }
      Equal(old_index~, new_index~, len~) => {
        let (next_old_cursor, next_new_cursor) = append_mapped_equal_lines(
          blocks, old_index, new_index, len, old_projected, new_projected, old_lines,
          new_lines, old_cursor, new_cursor,
        )
        old_cursor = next_old_cursor
        new_cursor = next_new_cursor
        index += 1
      }
      Delete(old_index~, old_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<old_len {
          rows.push(
            OldOnly(
              make_plain_diff_line(
                old_index + offset,
                old_view[old_index + offset].text,
              ),
            ),
          )
        }
        let (next_old_cursor, next_new_cursor) = append_mapped_change_rows(
          blocks, rows, old_projected, new_projected, old_lines, new_lines, old_cursor,
          new_cursor,
        )
        old_cursor = next_old_cursor
        new_cursor = next_new_cursor
        index += 1
      }
      Insert(new_index~, new_len~, ..) => {
        let rows : Array[DiffRow] = []
        for offset in 0..<new_len {
          rows.push(
            NewOnly(
              make_plain_diff_line(
                new_index + offset,
                new_view[new_index + offset].text,
              ),
            ),
          )
        }
        let (next_old_cursor, next_new_cursor) = append_mapped_change_rows(
          blocks, rows, old_projected, new_projected, old_lines, new_lines, old_cursor,
          new_cursor,
        )
        old_cursor = next_old_cursor
        new_cursor = next_new_cursor
        index += 1
      }
    }
  }
  append_ignored_source_gap(
    blocks, old_lines, new_lines, old_cursor, old_end, new_cursor, new_end,
  )
  let old_len = old_end - old_start
  let new_len = new_end - new_start
  { old_start, old_len, new_start, new_len, blocks }
}

///|
fn comment_aware_diff(
  old : ArrayView[String],
  new : ArrayView[String],
  context : Int,
  line_cleanup : Bool,
) -> DiffDocument {
  let old_lines = comment_projections(old)
  let new_lines = comment_projections(new)
  let old_projected = significant_projected_lines(old_lines)
  let new_projected = significant_projected_lines(new_lines)
  let old_code = projected_code_lines(old_projected)
  let new_code = projected_code_lines(new_projected)
  let hunks : Array[DiffHunk] = []
  for hunk in rendering_diff(old_code, new_code, line_cleanup).group(context~) {
    hunks.push(
      comment_hunk(hunk, old_projected, new_projected, old_lines, new_lines),
    )
  }
  { hunks, }
}

///|
/// Return a copy of an existing document whose comment-only and blank-line-only
/// rows are neutral context and whose corresponding hunks are removed. This is
/// primarily used to apply the same policy to structural diff documents.
pub fn DiffDocument::ignore_comments(
  self : DiffDocument,
  old~ : ArrayView[String],
  new~ : ArrayView[String],
) -> DiffDocument {
  let old_lines = comment_projections(old)
  let new_lines = comment_projections(new)
  let hunks : Array[DiffHunk] = []
  for hunk in self.hunks {
    let blocks : Array[DiffBlock] = []
    let mut has_change = false
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) => blocks.push(ContextBlock(lines.copy()))
        ChangeBlock(rows) =>
          if append_projected_rows(blocks, rows, old_lines, new_lines) {
            has_change = true
          }
        IgnoredBlock(rows) => blocks.push(IgnoredBlock(rows.copy()))
      }
    }
    if has_change {
      hunks.push({ ..hunk, blocks, })
    }
  }
  { hunks, }
}

///|
/// Calculate a MoonBit-aware diff and all renderer-neutral intraline changes.
/// When `ignore_comments` is enabled, comment-only and blank-line-only
/// differences are excluded from comparison but retained beside code changes.
pub fn diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  ignore_comments? : Bool = false,
) -> DiffDocument {
  if ignore_comments {
    return comment_aware_diff(old, new, context, line_cleanup)
  }
  let hunks : Array[DiffHunk] = []
  for hunk in rendering_diff(old, new, line_cleanup).group(context~) {
    hunks.push(semantic_hunk(hunk))
  }
  { hunks, }
}

///|
/// Calculate a plain Patience line diff without lexing, semantic cleanup, or
/// intraline changes.
pub fn line_diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
) -> DiffDocument {
  let hunks : Array[DiffHunk] = []
  for
    hunk in @diff.Diff(
      old~,
      new~,
      cutoff=CORE_LINE_DIFF_CUTOFF,
      algorithm=Patience,
    ).group(context~) {
    hunks.push(plain_hunk(hunk))
  }
  { hunks, }
}
