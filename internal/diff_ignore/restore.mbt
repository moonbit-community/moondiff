///|
fn push_segment(
  segments : Array[@model.DiffSegment],
  kind : @model.DiffSegmentKind,
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
fn ignored_source_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = [{ kind: Ignored, text }]
  { index, segments: segments[:] }
}

///|
fn visible_source_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
  { index, segments: segments[:] }
}

///|
fn changed_source_line(index : Int, view : SourceLineView) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = []
  let chars = view.source.to_array()
  let mut changed_start = chars.length()
  let mut changed_end = 0
  for char_index, char in chars {
    if !view.ignored[char_index] && !char.is_whitespace() {
      changed_start = @cmp.minimum(changed_start, char_index)
      changed_end = char_index + 1
    }
  }
  for char_index, char in chars {
    push_segment(
      segments,
      if view.ignored[char_index] {
        Ignored
      } else if char_index >= changed_start && char_index < changed_end {
        Changed
      } else {
        Unchanged
      },
      char.to_string(),
    )
  }
  { index, segments: segments[:] }
}

///|
/// Build a complete one-sided changed fragment directly from an original
/// source view. Filtered characters remain present as ignored segments.
pub fn SourceView::changed_rows(
  self : SourceView,
  old_side : Bool,
) -> ArrayView[@model.DiffRow] {
  let rows : Array[@model.DiffRow] = []
  for index, line in self.line_views {
    let changed = changed_source_line(index, line)
    rows.push(
      Changed(if old_side { OldOnly(changed) } else { NewOnly(changed) }),
    )
  }
  rows[:]
}

///|
// Reinsert every filtered character at its original position. Visible text
// keeps its calculated segment kind, while excluded text is always neutral.
fn restore_visible_line(
  line : @model.DiffLine,
  view : SourceLineView,
  source_index : Int,
) -> @model.DiffLine {
  let visible_kinds : Array[@model.DiffSegmentKind] = []
  for segment in line.segments {
    for _ in segment.text {
      visible_kinds.push(segment.kind)
    }
  }
  let segments : Array[@model.DiffSegment] = []
  let mut visible_index = 0
  for index, char in view.source.to_array() {
    let kind = if view.ignored[index] {
      @model.DiffSegmentKind::Ignored
    } else {
      let kind = visible_kinds.get(visible_index).unwrap_or(Unchanged)
      visible_index += 1
      kind
    }
    push_segment(segments, kind, char.to_string())
  }
  { index: source_index, segments: segments[:] }
}

///|
fn append_neutral_source_gap(
  rows : Array[@model.DiffRow],
  old : SourceView,
  new : SourceView,
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> Unit {
  let old_len = old_end - old_start
  let new_len = new_end - new_start
  let row_count = @cmp.maximum(old_len, new_len)
  for offset in 0..<row_count {
    let old_line = if offset < old_len {
      old.source_lines.get(old_start + offset)
    } else {
      None
    }
    let new_line = if offset < new_len {
      new.source_lines.get(new_start + offset)
    } else {
      None
    }
    match (old_line, new_line) {
      (Some(old_line), Some(new_line)) =>
        rows.push(
          Neutral(
            Paired(
              ignored_source_line(old_start + offset, old_line),
              ignored_source_line(new_start + offset, new_line),
            ),
          ),
        )
      (Some(old_line), None) =>
        rows.push(
          Neutral(OldOnly(ignored_source_line(old_start + offset, old_line))),
        )
      (None, Some(new_line)) =>
        rows.push(
          Neutral(NewOnly(ignored_source_line(new_start + offset, new_line))),
        )
      (None, None) => ()
    }
  }
}

///|
fn view_source_cursor(view : SourceView, index : Int) -> Int {
  if index < view.source_indices.length() {
    view.source_indices[index]
  } else {
    view.source_lines.length()
  }
}

///|
fn view_hunk_start(view : SourceView, index : Int) -> Int {
  if index == 0 {
    0
  } else {
    view.source_indices[index - 1] + 1
  }
}

///|
fn append_mapped_context(
  rows : Array[@model.DiffRow],
  line : @model.ContextLine,
  old : SourceView,
  new : SourceView,
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let old_target = old.source_indices[line.old_index]
  let new_target = new.source_indices[line.new_index]
  append_neutral_source_gap(
    rows, old, new, old_cursor, old_target, new_cursor, new_target,
  )
  let old_view = old.line_views[old_target]
  let new_view = new.line_views[new_target]
  if old_view.source == new_view.source {
    rows.push(
      Context({
        old_index: old_target,
        new_index: new_target,
        text: old_view.source,
      }),
    )
  } else {
    rows.push(
      Neutral(
        Paired(
          restore_visible_line(
            visible_source_line(line.old_index, line.text),
            old_view,
            old_target,
          ),
          restore_visible_line(
            visible_source_line(line.new_index, line.text),
            new_view,
            new_target,
          ),
        ),
      ),
    )
  }
  (old_target + 1, new_target + 1)
}

///|
fn pair_targets(
  pair : @model.DiffLinePair,
  old : SourceView,
  new : SourceView,
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  match pair {
    Paired(old_line, new_line) =>
      (old.source_indices[old_line.index], new.source_indices[new_line.index])
    OldOnly(old_line) => (old.source_indices[old_line.index], new_cursor)
    NewOnly(new_line) => (old_cursor, new.source_indices[new_line.index])
  }
}

///|
fn pair_differs_only_in_filtered_text(
  pair : @model.DiffLinePair,
  old : SourceView,
  new : SourceView,
  old_target : Int,
  new_target : Int,
) -> Bool {
  match pair {
    Paired(old_line, new_line) => {
      let old_view = old.line_views[old_target]
      let new_view = new.line_views[new_target]
      (old_view.has_ignored || new_view.has_ignored) &&
      old_view.visible == new_view.visible &&
      old_line.text() == new_line.text()
    }
    _ => false
  }
}

///|
fn restore_pair(
  pair : @model.DiffLinePair,
  old : SourceView,
  new : SourceView,
  old_target : Int,
  new_target : Int,
) -> @model.DiffLinePair {
  match pair {
    Paired(old_line, new_line) =>
      Paired(
        restore_visible_line(old_line, old.line_views[old_target], old_target),
        restore_visible_line(new_line, new.line_views[new_target], new_target),
      )
    OldOnly(old_line) =>
      OldOnly(
        restore_visible_line(old_line, old.line_views[old_target], old_target),
      )
    NewOnly(new_line) =>
      NewOnly(
        restore_visible_line(new_line, new.line_views[new_target], new_target),
      )
  }
}

///|
fn append_mapped_non_context(
  rows : Array[@model.DiffRow],
  pair : @model.DiffLinePair,
  neutral : Bool,
  old : SourceView,
  new : SourceView,
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let (old_target, new_target) = pair_targets(
    pair, old, new, old_cursor, new_cursor,
  )
  append_neutral_source_gap(
    rows, old, new, old_cursor, old_target, new_cursor, new_target,
  )
  let filtered_only = pair_differs_only_in_filtered_text(
    pair, old, new, old_target, new_target,
  )
  let restored = restore_pair(pair, old, new, old_target, new_target)
  rows.push(
    if neutral || filtered_only {
      Neutral(restored)
    } else {
      Changed(restored)
    },
  )
  let next_old = match pair {
    Paired(_, _) | OldOnly(_) => old_target + 1
    NewOnly(_) => old_cursor
  }
  let next_new = match pair {
    Paired(_, _) | NewOnly(_) => new_target + 1
    OldOnly(_) => new_cursor
  }
  (next_old, next_new)
}

///|
fn restore_row_range(
  input : ArrayView[@model.DiffRow],
  old : SourceView,
  new : SourceView,
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> Array[@model.DiffRow] {
  let rows : Array[@model.DiffRow] = []
  let mut old_cursor = old_start
  let mut new_cursor = new_start
  for row in input {
    let cursors = match row {
      Context(line) =>
        append_mapped_context(rows, line, old, new, old_cursor, new_cursor)
      Changed(pair) =>
        append_mapped_non_context(
          rows, pair, false, old, new, old_cursor, new_cursor,
        )
      Neutral(pair) =>
        append_mapped_non_context(
          rows, pair, true, old, new, old_cursor, new_cursor,
        )
    }
    old_cursor = cursors.0
    new_cursor = cursors.1
  }
  append_neutral_source_gap(
    rows, old, new, old_cursor, old_end, new_cursor, new_end,
  )
  rows
}

///|
/// Restore original text and indexes after comparison on complete filtered
/// source views. The returned stream covers both original views monotonically.
pub fn restore_rows(
  rows : ArrayView[@model.DiffRow],
  old~ : SourceView,
  new~ : SourceView,
) -> ArrayView[@model.DiffRow] {
  if rows.is_empty() {
    return []
  }
  restore_row_range(
    rows,
    old,
    new,
    0,
    old.source_lines.length(),
    0,
    new.source_lines.length(),
  )[:]
}

///|
/// Restore original text and indexes inside each traditional presentation
/// hunk. Filtered gaps become neutral rows but never create a hunk themselves.
pub fn restore_document(
  document : @model.HunkDocument,
  old~ : SourceView,
  new~ : SourceView,
) -> @model.HunkDocument {
  let hunks : Array[@model.DiffHunk] = []
  for hunk in document.hunks {
    let old_start = view_hunk_start(old, hunk.old_start)
    let new_start = view_hunk_start(new, hunk.new_start)
    let old_end = view_source_cursor(old, hunk.old_start + hunk.old_len)
    let new_end = view_source_cursor(new, hunk.new_start + hunk.new_len)
    let rows = restore_row_range(
      hunk.rows,
      old,
      new,
      old_start,
      old_end,
      new_start,
      new_end,
    )
    hunks.push({
      old_start,
      old_len: old_end - old_start,
      new_start,
      new_len: new_end - new_start,
      rows: rows[:],
    })
  }
  { hunks: hunks[:] }
}
