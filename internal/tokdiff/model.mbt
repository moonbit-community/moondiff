///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffSegmentKind = @model.DiffSegmentKind

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffSegment = @model.DiffSegment

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffLine = @model.DiffLine

///|
/// Compatibility alias for the renderer-neutral model type.
pub type ContextLine = @model.ContextLine

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffRow = @model.DiffRow

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffBlock = @model.DiffBlock

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffHunk = @model.DiffHunk

///|
/// Compatibility alias for the renderer-neutral model type.
pub type DiffDocument = @model.DiffDocument

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
  let buf = StringBuilder()
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
fn fallback_pair_segments(
  old_text : String,
  new_text : String,
  refine_words : Bool,
  budget : @worddiff.RefinementBudget,
) -> (Array[DiffSegment], Array[DiffSegment]) {
  if refine_words {
    match @worddiff.refine_line(old_text, new_text, budget~) {
      Some(segments) => return segments
      None => ()
    }
  }
  (plain_segments(old_text), plain_segments(new_text))
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
  { index, segments: segments[:] }
}

///|
fn make_plain_diff_line(index : Int, text : String) -> DiffLine {
  make_diff_line(index, plain_segments(text))
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
  budget : @worddiff.RefinementBudget,
) -> ArrayView[DiffRow] {
  let rows : Array[DiffRow] = []
  let equal_width = old_lines.length() == new_lines.length()
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
            fallback_pair_segments(
              old_lines[old_index].text,
              new_lines[new_index].text,
              equal_width,
              budget,
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
  } else if equal_width {
    for offset in 0..<old_lines.length() {
      let (old_segments, new_segments) = fallback_pair_segments(
        old_lines[offset].text,
        new_lines[offset].text,
        true,
        budget,
      )
      rows.push(
        Paired(
          make_diff_line(old_start + offset, old_segments),
          make_diff_line(new_start + offset, new_segments),
        ),
      )
    }
  } else {
    for offset, line in old_lines {
      rows.push(OldOnly(make_plain_diff_line(old_start + offset, line.text)))
    }
    for offset, line in new_lines {
      rows.push(NewOnly(make_plain_diff_line(new_start + offset, line.text)))
    }
  }
  rows[:]
}

///|
fn hunk_range(edits : ArrayView[@diff.Edit]) -> (Int, Int, Int, Int) {
  let (old_start, new_start, _, _) = edit_bounds(edits[0])
  let (_, _, old_end, new_end) = edit_bounds(edits[edits.length() - 1])
  (old_start, old_end - old_start, new_start, new_end - new_start)
}

///|
fn semantic_hunk(
  hunk : @diff.Hunk[ComparableLine],
  budget : @worddiff.RefinementBudget,
) -> DiffHunk {
  let blocks : Array[DiffBlock] = []
  let edits = hunk.edits()
  let old_view = hunk.old_view()
  let new_view = hunk.new_view()
  let mut index = 0
  while index < edits.length() {
    let replacement = if index + 1 < edits.length() {
      @worddiff.replacement_ranges(edits[index], edits[index + 1])
    } else {
      None
    }
    match replacement {
      Some(((old_start, old_end), (new_start, new_end))) => {
        blocks.push(
          ChangeBlock(
            semantic_change_rows(
              old_view.view(start=old_start, end=old_end),
              new_view.view(start=new_start, end=new_end),
              old_start,
              new_start,
              budget,
            ),
          ),
        )
        index += 2
      }
      None =>
        match edits[index] {
          Equal(old_index~, new_index~, len~) => {
            let lines : Array[ContextLine] = []
            for offset in 0..<len {
              lines.push({
                old_index: old_index + offset,
                new_index: new_index + offset,
                text: old_view[old_index + offset].text,
              })
            }
            blocks.push(ContextBlock(lines[:]))
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
            blocks.push(ChangeBlock(rows[:]))
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
            blocks.push(ChangeBlock(rows[:]))
            index += 1
          }
        }
    }
  }
  let (old_start, old_len, new_start, new_len) = hunk_range(edits)
  { old_start, old_len, new_start, new_len, blocks: blocks[:] }
}

///|
fn semantic_diff_with_refinement_budget(
  old : ArrayView[String],
  new : ArrayView[String],
  context : Int,
  line_cleanup : Bool,
  budget : @worddiff.RefinementBudget,
) -> DiffDocument {
  let hunks : Array[DiffHunk] = []
  for hunk in rendering_diff(old, new, line_cleanup).group(context~) {
    hunks.push(semantic_hunk(hunk, budget))
  }
  { hunks: hunks[:] }
}

///|
fn comment_aware_diff(
  old : ArrayView[String],
  new : ArrayView[String],
  context : Int,
  line_cleanup : Bool,
  budget : @worddiff.RefinementBudget,
) -> DiffDocument {
  let old_view = @diff_ignore.SourceView::from_lines(old, ignore_comments=true)
  let new_view = @diff_ignore.SourceView::from_lines(new, ignore_comments=true)
  @diff_ignore.restore_document(
    semantic_diff_with_refinement_budget(
      old_view.lines(),
      new_view.lines(),
      context,
      line_cleanup,
      budget,
    ),
    old=old_view,
    new=new_view,
  )
}

///|
fn diff_with_refinement_budget(
  old : ArrayView[String],
  new : ArrayView[String],
  context : Int,
  line_cleanup : Bool,
  ignore_comments : Bool,
  budget : @worddiff.RefinementBudget,
) -> DiffDocument {
  if ignore_comments {
    return comment_aware_diff(old, new, context, line_cleanup, budget)
  }
  semantic_diff_with_refinement_budget(old, new, context, line_cleanup, budget)
}

///|
/// Calculate a MoonBit-aware diff and all renderer-neutral intraline changes.
/// When `ignore_comments` is enabled, comment-only and blank-line-only
/// differences are excluded from comparison but retained beside code changes.
/// Word-level refinement used by bounded fallback paths allows 16,384 UTF-16
/// code units per side and shares document limits of 1,048,576 attempted code
/// units and 65,536 diff tokens. Exhaustion preserves plain rows, line numbers,
/// and hunk structure.
pub fn diff(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  ignore_comments? : Bool = false,
) -> DiffDocument {
  diff_with_refinement_budget(
    old,
    new,
    context,
    line_cleanup,
    ignore_comments,
    @worddiff.RefinementBudget::new(),
  )
}
