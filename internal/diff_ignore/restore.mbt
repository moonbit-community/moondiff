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
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Ignored, text }]
  }
  { index, segments: segments[:] }
}

///|
fn unchanged_visible_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
  { index, segments: segments[:] }
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
  let chars = view.source.to_array()
  let segments : Array[@model.DiffSegment] = []
  let mut visible_index = 0
  for index, ch in chars {
    let kind = if view.ignored[index] {
      @model.DiffSegmentKind::Ignored
    } else {
      let kind = visible_kinds.get(visible_index).unwrap_or(Unchanged)
      visible_index += 1
      kind
    }
    push_segment(segments, kind, ch.to_string())
  }
  { index: source_index, segments: segments[:] }
}

///|
fn append_ignored_source_gap(
  blocks : Array[@model.DiffBlock],
  old : SourceView,
  new : SourceView,
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> Unit {
  let rows : Array[@model.DiffRow] = []
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
          Paired(
            ignored_source_line(old_start + offset, old_line),
            ignored_source_line(new_start + offset, new_line),
          ),
        )
      (Some(old_line), None) =>
        rows.push(OldOnly(ignored_source_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(ignored_source_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  if !rows.is_empty() {
    blocks.push(IgnoredBlock(rows[:]))
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
fn append_mapped_context_lines(
  blocks : Array[@model.DiffBlock],
  lines : ArrayView[@model.ContextLine],
  old : SourceView,
  new : SourceView,
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let mapped : Array[@model.ContextLine] = []
  let ignored : Array[@model.DiffRow] = []
  let mut old_cursor = old_cursor
  let mut new_cursor = new_cursor
  fn flush_context(
    blocks : Array[@model.DiffBlock],
    mapped : Array[@model.ContextLine],
  ) -> Unit {
    if !mapped.is_empty() {
      blocks.push(ContextBlock(mapped.copy()[:]))
      mapped.clear()
    }
  }
  fn flush_ignored(
    blocks : Array[@model.DiffBlock],
    ignored : Array[@model.DiffRow],
  ) -> Unit {
    if !ignored.is_empty() {
      blocks.push(IgnoredBlock(ignored.copy()[:]))
      ignored.clear()
    }
  }
  for line in lines {
    let old_target = old.source_indices[line.old_index]
    let new_target = new.source_indices[line.new_index]
    if old_cursor < old_target || new_cursor < new_target {
      flush_context(blocks, mapped)
      flush_ignored(blocks, ignored)
      append_ignored_source_gap(
        blocks, old, new, old_cursor, old_target, new_cursor, new_target,
      )
    }
    let old_view = old.line_views[old_target]
    let new_view = new.line_views[new_target]
    if old_view.has_ignored || new_view.has_ignored {
      flush_context(blocks, mapped)
      ignored.push(
        Paired(
          restore_visible_line(
            unchanged_visible_line(line.old_index, line.text),
            old_view,
            old_target,
          ),
          restore_visible_line(
            unchanged_visible_line(line.new_index, line.text),
            new_view,
            new_target,
          ),
        ),
      )
    } else {
      flush_ignored(blocks, ignored)
      mapped.push({
        old_index: old_target,
        new_index: new_target,
        text: old_view.source,
      })
    }
    old_cursor = old_target + 1
    new_cursor = new_target + 1
  }
  flush_context(blocks, mapped)
  flush_ignored(blocks, ignored)
  (old_cursor, new_cursor)
}

///|
fn append_mapped_rows(
  blocks : Array[@model.DiffBlock],
  rows : ArrayView[@model.DiffRow],
  as_ignored : Bool,
  old : SourceView,
  new : SourceView,
  old_cursor : Int,
  new_cursor : Int,
) -> (Int, Int) {
  let changed : Array[@model.DiffRow] = []
  let ignored : Array[@model.DiffRow] = []
  let mut old_cursor = old_cursor
  let mut new_cursor = new_cursor
  fn flush_changed(
    blocks : Array[@model.DiffBlock],
    changed : Array[@model.DiffRow],
  ) -> Unit {
    if !changed.is_empty() {
      blocks.push(ChangeBlock(changed.copy()[:]))
      changed.clear()
    }
  }
  fn flush_ignored(
    blocks : Array[@model.DiffBlock],
    ignored : Array[@model.DiffRow],
  ) -> Unit {
    if !ignored.is_empty() {
      blocks.push(IgnoredBlock(ignored.copy()[:]))
      ignored.clear()
    }
  }
  for row in rows {
    let (old_target, new_target) = match row {
      Paired(old_line, new_line) =>
        (old.source_indices[old_line.index], new.source_indices[new_line.index])
      OldOnly(old_line) => (old.source_indices[old_line.index], new_cursor)
      NewOnly(new_line) => (old_cursor, new.source_indices[new_line.index])
    }
    if old_cursor < old_target || new_cursor < new_target {
      flush_changed(blocks, changed)
      flush_ignored(blocks, ignored)
      append_ignored_source_gap(
        blocks, old, new, old_cursor, old_target, new_cursor, new_target,
      )
    }
    let row_is_ignored = as_ignored ||
      (match row {
        Paired(old_line, new_line) => {
          let old_line_view = old.line_views[old_target]
          let new_line_view = new.line_views[new_target]
          (old_line_view.has_ignored || new_line_view.has_ignored) &&
          old_line_view.visible == new_line_view.visible &&
          old_line.text() == new_line.text()
        }
        _ => false
      })
    let restored : @model.DiffRow = match row {
      Paired(old_line, new_line) => {
        old_cursor = old_target + 1
        new_cursor = new_target + 1
        Paired(
          restore_visible_line(old_line, old.line_views[old_target], old_target),
          restore_visible_line(new_line, new.line_views[new_target], new_target),
        )
      }
      OldOnly(old_line) => {
        old_cursor = old_target + 1
        OldOnly(
          restore_visible_line(old_line, old.line_views[old_target], old_target),
        )
      }
      NewOnly(new_line) => {
        new_cursor = new_target + 1
        NewOnly(
          restore_visible_line(new_line, new.line_views[new_target], new_target),
        )
      }
    }
    if row_is_ignored {
      flush_changed(blocks, changed)
      ignored.push(restored)
    } else {
      flush_ignored(blocks, ignored)
      changed.push(restored)
    }
  }
  flush_changed(blocks, changed)
  flush_ignored(blocks, ignored)
  (old_cursor, new_cursor)
}

///|
/// Restore original text and indexes after comparison on a filtered source
/// view. Removed lines and fragments are emitted only inside visible,
/// code-driven hunks and are always neutral, so they cannot create a hunk.
pub fn restore_document(
  document : @model.DiffDocument,
  old~ : SourceView,
  new~ : SourceView,
) -> @model.DiffDocument {
  let hunks : Array[@model.DiffHunk] = []
  for hunk in document.hunks {
    let old_start = view_hunk_start(old, hunk.old_start)
    let new_start = view_hunk_start(new, hunk.new_start)
    let old_end = view_source_cursor(old, hunk.old_start + hunk.old_len)
    let new_end = view_source_cursor(new, hunk.new_start + hunk.new_len)
    let blocks : Array[@model.DiffBlock] = []
    let mut old_cursor = old_start
    let mut new_cursor = new_start
    for block in hunk.blocks {
      let cursors = match block {
        ContextBlock(lines) =>
          append_mapped_context_lines(
            blocks, lines, old, new, old_cursor, new_cursor,
          )
        ChangeBlock(rows) =>
          append_mapped_rows(
            blocks, rows, false, old, new, old_cursor, new_cursor,
          )
        IgnoredBlock(rows) =>
          append_mapped_rows(
            blocks, rows, true, old, new, old_cursor, new_cursor,
          )
      }
      old_cursor = cursors.0
      new_cursor = cursors.1
    }
    append_ignored_source_gap(
      blocks, old, new, old_cursor, old_end, new_cursor, new_end,
    )
    hunks.push({
      old_start,
      old_len: old_end - old_start,
      new_start,
      new_len: new_end - new_start,
      blocks: blocks[:],
    })
  }
  { hunks: hunks[:] }
}
