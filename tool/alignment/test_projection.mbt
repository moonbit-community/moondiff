///|
// One original line with test-owned characters removed from comparison.
// `ignored` is indexed by Unicode scalar value, matching CST location columns.
priv struct SourceLineProjection {
  source : String
  projected : String
  ignored : Array[Bool]
  has_ignored : Bool
}

///|
// One source with top-level test characters removed from comparison.
// Projected line indexes are dense; `source_indices` maps them back to this
// projection's local original lines, while `projected_indices` is the inverse.
// Slices retain a global line offset so CST spans can be projected directly.
priv struct SourceProjection {
  source_lines : Array[String]
  line_projections : Array[SourceLineProjection]
  lines : Array[String]
  source_indices : Array[Int]
  projected_indices : Array[Int]
  source_line_offset : Int
}

///|
fn projection_line_is_blank(line : String) -> Bool {
  for ch in line {
    if !ch.is_whitespace() {
      return false
    }
  }
  true
}

///|
fn mark_projection_range(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  line : Int,
  start : Int,
  end_ : Int,
) -> Unit {
  guard ignored.get(line) is Some(mask) else { return }
  let start = @cmp.minimum(@cmp.maximum(start, 0), mask.length())
  let end_ = @cmp.minimum(@cmp.maximum(end_, start), mask.length())
  touched[line] = true
  for index in start..<end_ {
    mask[index] = true
  }
}

///|
fn mark_projection_line(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  line : Int,
) -> Unit {
  guard ignored.get(line) is Some(mask) else { return }
  touched[line] = true
  for index in 0..<mask.length() {
    mask[index] = true
  }
}

///|
fn mark_test_location(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  range : IgnoredTestRange,
) -> Unit {
  let start_line = range.loc.start.lnum - 1
  let end_line = range.loc.end.lnum - 1
  let start_col = @cmp.maximum(range.loc.start.column() - 1, 0)
  let end_col = @cmp.maximum(range.loc.end.column() - 1, 0)
  if start_line == end_line {
    mark_projection_range(ignored, touched, start_line, start_col, end_col)
    return
  }
  if ignored.get(start_line) is Some(mask) {
    mark_projection_range(
      ignored,
      touched,
      start_line,
      start_col,
      mask.length(),
    )
  }
  for line in (start_line + 1)..<end_line {
    mark_projection_line(ignored, touched, line)
  }
  if end_col > 0 {
    mark_projection_range(ignored, touched, end_line, 0, end_col)
  }
}

///|
fn mark_test_separator_lines(
  source_lines : ArrayView[String],
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  range : IgnoredTestRange,
) -> Unit {
  let first = range.loc.start.lnum - 1
  let end_line = range.loc.end.lnum - 1
  let end_col = @cmp.maximum(range.loc.end.column() - 1, 0)
  let last = if end_col == 0 && end_line > first {
    end_line - 1
  } else {
    end_line
  }
  let mut before = first - 1
  while before >= 0 &&
        source_lines.get(before) is Some(line) &&
        projection_line_is_blank(line) {
    mark_projection_line(ignored, touched, before)
    before -= 1
  }
  let mut after = last + 1
  while after < source_lines.length() &&
        projection_line_is_blank(source_lines[after]) {
    mark_projection_line(ignored, touched, after)
    after += 1
  }
}

///|
// Whitespace directly beside test syntax belongs to the ignored fragment. In
// particular, this removes indentation and the spacing before a same-line
// ordinary comment without consuming that comment or another visible suffix.
fn expand_ignored_line_whitespace(
  chars : ArrayView[Char],
  ignored : Array[Bool],
) -> Unit {
  let mut start = 0
  while start < chars.length() {
    if !chars[start].is_whitespace() {
      start += 1
      continue
    }
    let mut end_ = start + 1
    while end_ < chars.length() && chars[end_].is_whitespace() {
      end_ += 1
    }
    if (start > 0 && ignored[start - 1]) ||
      (end_ < chars.length() && ignored[end_]) {
      for index in start..<end_ {
        ignored[index] = true
      }
    }
    start = end_
  }
}

///|
fn SourceLineProjection::fully_ignored(self : SourceLineProjection) -> Bool {
  self.has_ignored && self.ignored.all(value => value)
}

///|
fn source_projection_from_lines(
  line_projections : Array[SourceLineProjection],
  source_line_offset : Int,
) -> SourceProjection {
  let source_lines : Array[String] = []
  let lines : Array[String] = []
  let source_indices : Array[Int] = []
  let projected_indices = Array::make(line_projections.length(), -1)
  for source_index, line in line_projections {
    source_lines.push(line.source)
    if !line.fully_ignored() {
      projected_indices[source_index] = lines.length()
      lines.push(line.projected)
      source_indices.push(source_index)
    }
  }
  {
    source_lines,
    line_projections,
    lines,
    source_indices,
    projected_indices,
    source_line_offset,
  }
}

///|
fn make_source_projection(
  source : String,
  ignored_tests : ArrayView[IgnoredTestRange],
) -> SourceProjection {
  let source_lines = if source == "" {
    []
  } else {
    @source_text.split_lines(source)
  }
  let source_chars : Array[Array[Char]] = source_lines.map(line => {
    line.to_array()
  })
  let ignored : Array[Array[Bool]] = source_chars.map(chars => {
    Array::make(chars.length(), false)
  })
  let touched = Array::make(source_lines.length(), false)
  for range in ignored_tests {
    mark_test_location(ignored, touched, range)
    mark_test_separator_lines(source_lines, ignored, touched, range)
  }
  let line_projections : Array[SourceLineProjection] = []
  for index, chars in source_chars {
    let mask = ignored[index]
    expand_ignored_line_whitespace(chars, mask)
    let projected_chars : Array[Char] = []
    for char_index, ch in chars {
      if !mask[char_index] {
        projected_chars.push(ch)
      }
    }
    line_projections.push({
      source: source_lines[index],
      projected: String::from_array(projected_chars),
      ignored: mask,
      has_ignored: touched[index],
    })
  }
  source_projection_from_lines(line_projections, 0)
}

///|
fn SourceProjection::source(self : SourceProjection) -> String {
  self.lines.join("\n")
}

///|
fn SourceProjection::slice(
  self : SourceProjection,
  source_start : Int,
  source_len : Int,
) -> SourceProjection {
  let local_start = @cmp.minimum(
    @cmp.maximum(source_start - self.source_line_offset, 0),
    self.line_projections.length(),
  )
  let local_end = @cmp.minimum(
    local_start + @cmp.maximum(source_len, 0),
    self.line_projections.length(),
  )
  source_projection_from_lines(
    self.line_projections[local_start:local_end].to_owned(),
    self.source_line_offset + local_start,
  )
}

///|
fn unit_source_projection(
  projection : SourceProjection,
  unit : ImplUnit?,
) -> SourceProjection {
  if unit is Some(unit) {
    let source_len = if unit.source == "" {
      0
    } else {
      @source_text.split_lines(unit.source).length()
    }
    projection.slice(unit.start_line - 1, source_len)
  } else {
    source_projection_from_lines([], 0)
  }
}

///|
fn span_character_bounds(
  span : @span.SingleLineSpan,
  line_len : Int,
) -> (Int, Int) {
  let start = if span.start_col == 0 {
    0
  } else {
    @cmp.maximum(span.start_col - 1, 0)
  }
  let end_ = if span.start_col == 0 { span.end_col } else { span.end_col - 1 }
  (
    @cmp.minimum(start, line_len),
    @cmp.minimum(@cmp.maximum(end_, start), line_len),
  )
}

///|
fn projected_boundary(line : SourceLineProjection, boundary : Int) -> Int {
  let mut projected = 0
  for index in 0..<@cmp.minimum(boundary, line.ignored.length()) {
    if !line.ignored[index] {
      projected += 1
    }
  }
  projected
}

///|
fn SourceProjection::project_span(
  self : SourceProjection,
  span : @span.SingleLineSpan,
) -> @span.SingleLineSpan? {
  let source_index = span.line - 1 - self.source_line_offset
  guard self.projected_indices.get(source_index) is Some(projected_index) &&
    projected_index >= 0 &&
    self.line_projections.get(source_index) is Some(line) else {
    return None
  }
  let (start, end_) = span_character_bounds(span, line.ignored.length())
  if start >= end_ {
    return None
  }
  for index in start..<end_ {
    if line.ignored[index] {
      return None
    }
  }
  let projected_start = projected_boundary(line, start)
  let projected_end = projected_boundary(line, end_)
  if projected_start >= projected_end {
    None
  } else {
    Some({
      line: projected_index + 1,
      start_col: projected_start + 1,
      end_col: projected_end + 1,
    })
  }
}

///|
// Structural positions keep original CST line numbers. Move both their own
// and opposite spans into the dense non-test projection before hunk building.
// Any syntax span touching test-owned text is deliberately omitted.
fn project_matched_positions(
  positions : ArrayView[MatchedPos],
  own : SourceProjection,
  opposite : SourceProjection,
) -> Array[MatchedPos] {
  let projected : Array[MatchedPos] = []
  for position in positions {
    guard own.project_span(position.pos) is Some(pos) else { continue }
    let kind = match position.kind {
      Novel => MatchKind::Novel
      Unchanged(opposite_pos~) => {
        let mapped : Array[@span.SingleLineSpan] = []
        for span in opposite_pos {
          if opposite.project_span(span) is Some(projected_span) {
            mapped.push(projected_span)
          }
        }
        Unchanged(opposite_pos=mapped)
      }
    }
    projected.push({ kind, pos })
  }
  projected
}

///|
fn ignored_test_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Ignored, text }]
  }
  { index, segments: segments[:] }
}

///|
fn unchanged_projected_line(index : Int, text : String) -> @model.DiffLine {
  let segments : Array[@model.DiffSegment] = if text == "" {
    []
  } else {
    [{ kind: Unchanged, text }]
  }
  { index, segments: segments[:] }
}

///|
// Reinsert every ignored character at its original position. Visible text
// keeps its calculated segment kind, while test-owned text is always neutral.
fn restore_projected_line(
  line : @model.DiffLine,
  projection : SourceLineProjection,
  source_index : Int,
) -> @model.DiffLine {
  let visible_kinds : Array[@model.DiffSegmentKind] = []
  for segment in line.segments {
    for _ in segment.text {
      visible_kinds.push(segment.kind)
    }
  }
  let chars = projection.source.to_array()
  let segments : Array[@model.DiffSegment] = []
  let mut visible_index = 0
  for index, ch in chars {
    let kind = if projection.ignored[index] {
      @model.DiffSegmentKind::Ignored
    } else {
      let kind = visible_kinds.get(visible_index).unwrap_or(Unchanged)
      visible_index += 1
      kind
    }
    push_ast_segment(segments, kind, ch.to_string())
  }
  { index: source_index, segments: segments[:] }
}

///|
fn append_ignored_test_gap(
  blocks : Array[@model.DiffBlock],
  old : SourceProjection,
  new : SourceProjection,
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
            ignored_test_line(old_start + offset, old_line),
            ignored_test_line(new_start + offset, new_line),
          ),
        )
      (Some(old_line), None) =>
        rows.push(OldOnly(ignored_test_line(old_start + offset, old_line)))
      (None, Some(new_line)) =>
        rows.push(NewOnly(ignored_test_line(new_start + offset, new_line)))
      (None, None) => ()
    }
  }
  if !rows.is_empty() {
    blocks.push(IgnoredBlock(rows[:]))
  }
}

///|
fn projection_source_cursor(projection : SourceProjection, index : Int) -> Int {
  if index < projection.source_indices.length() {
    projection.source_indices[index]
  } else {
    projection.source_lines.length()
  }
}

///|
fn projection_hunk_start(projection : SourceProjection, index : Int) -> Int {
  if index == 0 {
    0
  } else {
    projection.source_indices[index - 1] + 1
  }
}

///|
fn append_mapped_context_lines(
  blocks : Array[@model.DiffBlock],
  lines : ArrayView[@model.ContextLine],
  old : SourceProjection,
  new : SourceProjection,
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
      append_ignored_test_gap(
        blocks, old, new, old_cursor, old_target, new_cursor, new_target,
      )
    }
    let old_projection = old.line_projections[old_target]
    let new_projection = new.line_projections[new_target]
    if old_projection.has_ignored || new_projection.has_ignored {
      flush_context(blocks, mapped)
      ignored.push(
        Paired(
          restore_projected_line(
            unchanged_projected_line(line.old_index, line.text),
            old_projection,
            old_target,
          ),
          restore_projected_line(
            unchanged_projected_line(line.new_index, line.text),
            new_projection,
            new_target,
          ),
        ),
      )
    } else {
      flush_ignored(blocks, ignored)
      mapped.push({
        old_index: old_target,
        new_index: new_target,
        text: old_projection.source,
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
  old : SourceProjection,
  new : SourceProjection,
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
      append_ignored_test_gap(
        blocks, old, new, old_cursor, old_target, new_cursor, new_target,
      )
    }
    let row_is_ignored = as_ignored ||
      (match row {
        Paired(old_line, new_line) => {
          let old_line_projection = old.line_projections[old_target]
          let new_line_projection = new.line_projections[new_target]
          (old_line_projection.has_ignored || new_line_projection.has_ignored) &&
          old_line_projection.projected == new_line_projection.projected &&
          old_line.text() == new_line.text()
        }
        _ => false
      })
    let restored : @model.DiffRow = match row {
      Paired(old_line, new_line) => {
        old_cursor = old_target + 1
        new_cursor = new_target + 1
        Paired(
          restore_projected_line(
            old_line,
            old.line_projections[old_target],
            old_target,
          ),
          restore_projected_line(
            new_line,
            new.line_projections[new_target],
            new_target,
          ),
        )
      }
      OldOnly(old_line) => {
        old_cursor = old_target + 1
        OldOnly(
          restore_projected_line(
            old_line,
            old.line_projections[old_target],
            old_target,
          ),
        )
      }
      NewOnly(new_line) => {
        new_cursor = new_target + 1
        NewOnly(
          restore_projected_line(
            new_line,
            new.line_projections[new_target],
            new_target,
          ),
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
// Restore original text and indexes after comparison on the character-level
// non-test projection. Removed lines and fragments are emitted only inside
// code-driven hunks and are always neutral, so they cannot create a hunk.
fn restore_projected_document(
  document : @model.DiffDocument,
  old : SourceProjection,
  new : SourceProjection,
) -> @model.DiffDocument {
  let hunks : Array[@model.DiffHunk] = []
  for hunk in document.hunks {
    let old_start = projection_hunk_start(old, hunk.old_start)
    let new_start = projection_hunk_start(new, hunk.new_start)
    let old_end = projection_source_cursor(old, hunk.old_start + hunk.old_len)
    let new_end = projection_source_cursor(new, hunk.new_start + hunk.new_len)
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
    append_ignored_test_gap(
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
