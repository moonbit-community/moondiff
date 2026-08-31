///|
priv struct DetailedUnitResult {
  document : @model.HunkDocument
  fallback : FallbackReason?
}

///|
priv enum AstBuildResult {
  AstDocument(@model.HunkDocument)
  AstPositionsOutOfBounds(ArrayView[DiffSide])
  AstGraphLimitExceeded
}

///|
type NovelRangeMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|
fn add_novel_range(
  ranges : NovelRangeMap,
  line : Int,
  start_col : Int,
  end_col : Int,
) -> Unit {
  if line >= 0 && end_col > start_col {
    ranges.get_or_init(line, fn() { [] }).push((start_col, end_col))
  }
}

///|
fn collect_novel_ranges(positions : ArrayView[MatchedPos]) -> NovelRangeMap {
  let ranges = @hashmap.HashMap([])
  for position in positions {
    if position.kind.is_novel() {
      add_novel_range(
        ranges,
        @syntax.line_index(position.pos),
        position.pos.start_col,
        position.pos.end_col,
      )
    }
  }
  ranges
}

///|
fn push_ast_segment(
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
    segments[last] = { kind, text: previous.text + text, }
  } else {
    segments.push({ kind, text, })
  }
}

///|
// Keep a visually continuous structural change in one highlight. Whitespace
// is absent from the matching tree, so two adjacent novel syntax atoms can
// otherwise render as separate highlights with an unhighlighted gap. Only
// bridge whitespace bounded by changed source on both sides; indentation,
// trailing whitespace, and gaps containing unchanged syntax stay unchanged.
fn bridge_ast_changed_whitespace(
  chars : ArrayView[Char],
  mask : Array[Bool],
) -> Unit {
  let mut start = 0
  while start < chars.length() {
    if mask[start] {
      start += 1
      continue
    }
    let mut end_ = start + 1
    let mut whitespace_only = chars[start].is_whitespace()
    while end_ < chars.length() && !mask[end_] {
      if !chars[end_].is_whitespace() {
        whitespace_only = false
      }
      end_ += 1
    }
    if whitespace_only &&
      start > 0 &&
      mask[start - 1] &&
      end_ < chars.length() &&
      mask[end_] {
      for index in start..<end_ {
        mask[index] = true
      }
    }
    start = end_
  }
}

///|
fn ast_line_segments_impl(
  text : String,
  line_ranges : Array[(Int, Int)]?,
) -> Array[@model.DiffSegment] {
  let chars = text.to_array()
  if chars.is_empty() {
    return []
  }
  let mask : Array[Bool] = []
  for _ in chars {
    mask.push(false)
  }
  if line_ranges is Some(line_ranges) {
    for range in line_ranges {
      let (start_col, end_col) = range
      let start = if start_col == 0 {
        0
      } else {
        @cmp.maximum(start_col - 1, 0)
      }
      let end_ = @cmp.minimum(
        if start_col == 0 {
          end_col
        } else {
          end_col - 1
        },
        chars.length(),
      )
      for index in start..<end_ {
        mask[index] = true
      }
    }
  }
  bridge_ast_changed_whitespace(chars, mask)
  let segments : Array[@model.DiffSegment] = []
  let mut start = 0
  while start < chars.length() {
    let changed = mask[start]
    let mut end_ = start + 1
    while end_ < chars.length() && mask[end_] == changed {
      end_ += 1
    }
    push_ast_segment(
      segments,
      if changed {
        Changed
      } else {
        Unchanged
      },
      String::from_array(chars[start:end_].to_owned()),
    )
    start = end_
  }
  segments
}

///|
fn ast_diff_line(
  index : Int,
  text : String,
  ranges : NovelRangeMap,
) -> @model.DiffLine {
  let segments = ast_line_segments_impl(text, ranges.get(index))
  { index, segments: segments[:], }
}

///|
fn ast_pair_is_context(
  pair : (Int?, Int?),
  hunk : @ast_hunks.AstHunk,
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
) -> Bool {
  match pair {
    (Some(old_line), Some(new_line)) =>
      !hunk.novel_lhs.contains(old_line) &&
      !hunk.novel_rhs.contains(new_line) &&
      old_lines[old_line] == new_lines[new_line]
    _ => false
  }
}

///|
fn ast_change_row(
  pair : (Int?, Int?),
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_ranges : NovelRangeMap,
  new_ranges : NovelRangeMap,
) -> @model.DiffRow {
  match pair {
    (Some(old_line), Some(new_line)) =>
      Paired(
        ast_diff_line(old_line, old_lines[old_line], old_ranges),
        ast_diff_line(new_line, new_lines[new_line], new_ranges),
      )
    (Some(old_line), None) =>
      OldOnly(ast_diff_line(old_line, old_lines[old_line], old_ranges))
    (None, Some(new_line)) =>
      NewOnly(ast_diff_line(new_line, new_lines[new_line], new_ranges))
    (None, None) => panic()
  }
}

///|
fn ast_hunk_blocks(
  pairs : ArrayView[(Int?, Int?)],
  hunk : @ast_hunks.AstHunk,
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_ranges : NovelRangeMap,
  new_ranges : NovelRangeMap,
) -> ArrayView[@model.DiffBlock] {
  let blocks : Array[@model.DiffBlock] = []
  let context_lines : Array[@model.ContextLine] = []
  let change_rows : Array[@model.DiffRow] = []
  for pair in pairs {
    if ast_pair_is_context(pair, hunk, old_lines, new_lines) {
      if !change_rows.is_empty() {
        blocks.push(ChangeBlock(change_rows.copy()[:]))
        change_rows.clear()
      }
      guard pair is (Some(old_index), Some(new_index)) else { panic() }
      context_lines.push({ old_index, new_index, text: old_lines[old_index], })
    } else {
      if !context_lines.is_empty() {
        blocks.push(ContextBlock(context_lines.copy()[:]))
        context_lines.clear()
      }
      change_rows.push(
        ast_change_row(pair, old_lines, new_lines, old_ranges, new_ranges),
      )
    }
  }
  if !context_lines.is_empty() {
    blocks.push(ContextBlock(context_lines[:]))
  }
  if !change_rows.is_empty() {
    blocks.push(ChangeBlock(change_rows[:]))
  }
  blocks[:]
}

///|
fn ast_line_is_novel(line : Int?, novel_lines : @ast_hunks.LineSet) -> Bool {
  line is Some(line) && novel_lines.contains(line)
}

///|
fn ast_pair_side_is_changed(
  line : Int?,
  opposite : Int?,
  novel_lines : @ast_hunks.LineSet,
) -> Bool {
  ast_line_is_novel(line, novel_lines) || (line is Some(_) && opposite is None)
}

///|
fn ast_pair_has_change(pair : (Int?, Int?), hunk : @ast_hunks.AstHunk) -> Bool {
  ast_pair_side_is_changed(pair.0, pair.1, hunk.novel_lhs) ||
  ast_pair_side_is_changed(pair.1, pair.0, hunk.novel_rhs)
}

///|
fn ast_should_render_as_block_replacement(
  segment : ArrayView[(Int?, Int?)],
  hunk : @ast_hunks.AstHunk,
) -> Bool {
  let lhs_lines : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let rhs_lines : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let mut all_present_sides_are_novel = true
  for pair in segment {
    let lhs_novel = ast_pair_side_is_changed(pair.0, pair.1, hunk.novel_lhs)
    let rhs_novel = ast_pair_side_is_changed(pair.1, pair.0, hunk.novel_rhs)
    if pair.0 is Some(line) {
      if lhs_novel {
        lhs_lines[line] = true
      } else {
        all_present_sides_are_novel = false
      }
    }
    if pair.1 is Some(line) {
      if rhs_novel {
        rhs_lines[line] = true
      } else {
        all_present_sides_are_novel = false
      }
    }
  }
  all_present_sides_are_novel &&
  lhs_lines.length() >= 2 &&
  rhs_lines.length() >= 2
}

///|
fn append_ast_segment_lines(
  output : Array[(Int?, Int?)],
  segment : ArrayView[(Int?, Int?)],
  hunk : @ast_hunks.AstHunk,
) -> Unit {
  if ast_should_render_as_block_replacement(segment, hunk) {
    for pair in segment {
      if ast_pair_side_is_changed(pair.0, pair.1, hunk.novel_lhs) {
        output.push((pair.0, None))
      }
    }
    for pair in segment {
      if ast_pair_side_is_changed(pair.1, pair.0, hunk.novel_rhs) {
        output.push((None, pair.1))
      }
    }
  } else {
    output.push_iter(segment.iter())
  }
}

///|
fn reduce_ast_sparse_replacements(
  lines : ArrayView[(Int?, Int?)],
  hunk : @ast_hunks.AstHunk,
) -> Array[(Int?, Int?)] {
  let output : Array[(Int?, Int?)] = []
  let segment : Array[(Int?, Int?)] = []
  for pair in lines {
    if ast_pair_has_change(pair, hunk) {
      segment.push(pair)
    } else {
      append_ast_segment_lines(output, segment, hunk)
      segment.clear()
      output.push(pair)
    }
  }
  append_ast_segment_lines(output, segment, hunk)
  output
}

///|
fn ast_hunk_side_range(
  pairs : ArrayView[(Int?, Int?)],
  old_side : Bool,
) -> (Int, Int) {
  let first : Ref[Int?] = Ref(None)
  let last : Ref[Int?] = Ref(None)
  let fallback : Ref[Int?] = Ref(None)
  for pair in pairs {
    let selected = if old_side { pair.0 } else { pair.1 }
    let opposite = if old_side { pair.1 } else { pair.0 }
    if selected is Some(line) {
      if first.val is None {
        first.val = Some(line)
      }
      last.val = Some(line)
    } else if fallback.val is None && opposite is Some(line) {
      fallback.val = Some(line)
    }
  }
  match (first.val, last.val) {
    (Some(start), Some(end_)) => (start, end_ - start + 1)
    _ => (fallback.val.unwrap_or(0), 0)
  }
}

///|
fn ast_document_from_positions(
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  lhs_positions : ArrayView[MatchedPos],
  rhs_positions : ArrayView[MatchedPos],
  context : Int,
  reduce_sparse_replacements : Bool,
) -> AstBuildResult {
  let out_of_bounds = ast_position_out_of_bounds_sides(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  if !out_of_bounds.is_empty() {
    return AstPositionsOutOfBounds(out_of_bounds[:])
  }
  let matched_lines = @ast_hunks.all_matched_lines_filled(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  let ast_hunks = @ast_hunks.merge_adjacent_hunks(
    @ast_hunks.matched_pos_to_hunks(lhs_positions, rhs_positions),
    matched_lines,
    context,
  )
  let old_ranges = collect_novel_ranges(lhs_positions)
  let new_ranges = collect_novel_ranges(rhs_positions)
  let hunks : Array[@model.DiffHunk] = []
  for hunk in ast_hunks {
    let (start, end_) = @ast_hunks.contextual_index_range_for_hunk(
      hunk,
      matched_lines,
      context + 1,
    )
    let pairs = if reduce_sparse_replacements {
      reduce_ast_sparse_replacements(matched_lines[start:end_], hunk)
    } else {
      matched_lines[start:end_].to_owned()
    }
    let (old_start, old_len) = ast_hunk_side_range(pairs, true)
    let (new_start, new_len) = ast_hunk_side_range(pairs, false)
    hunks.push({
      old_start,
      old_len,
      new_start,
      new_len,
      blocks: ast_hunk_blocks(
        pairs, hunk, old_lines, new_lines, old_ranges, new_ranges,
      ),
    })
  }
  AstDocument({ hunks: hunks[:], })
}

///|
fn span_columns_are_in_bounds(
  span : @span.SingleLineSpan,
  line_len : Int,
) -> Bool {
  if span.start_col == 0 {
    span.end_col >= 0 && span.end_col <= line_len + 1
  } else {
    span.start_col >= 1 &&
    span.start_col <= line_len + 1 &&
    span.end_col >= span.start_col &&
    span.end_col <= line_len + 1
  }
}

///|
fn span_is_in_bounds(
  span : @span.SingleLineSpan,
  lines : ArrayView[String],
) -> Bool {
  if span.line < 1 || span.line > lines.length() {
    return false
  }
  guard lines.get(span.line - 1) is Some(line) else { return false }
  span_columns_are_in_bounds(span, line.to_array().length())
}

///|
fn matched_position_bounds(
  positions : ArrayView[MatchedPos],
  own_lines : ArrayView[String],
  opposite_lines : ArrayView[String],
) -> (Bool, Bool) {
  let mut own_out_of_bounds = false
  let mut opposite_out_of_bounds = false
  for position in positions {
    if !span_is_in_bounds(position.pos, own_lines) {
      own_out_of_bounds = true
    }
    if position.kind is Unchanged(opposite_pos~) {
      for span in opposite_pos {
        if !span_is_in_bounds(span, opposite_lines) {
          opposite_out_of_bounds = true
        }
      }
    }
  }
  (own_out_of_bounds, opposite_out_of_bounds)
}

///|
fn ast_position_out_of_bounds_sides(
  lhs_positions : ArrayView[MatchedPos],
  rhs_positions : ArrayView[MatchedPos],
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
) -> Array[DiffSide] {
  let (lhs_old, lhs_new) = matched_position_bounds(
    lhs_positions, old_lines, new_lines,
  )
  let (rhs_new, rhs_old) = matched_position_bounds(
    rhs_positions, new_lines, old_lines,
  )
  let sides : Array[DiffSide] = []
  if lhs_old || rhs_old {
    sides.push(Old)
  }
  if lhs_new || rhs_new {
    sides.push(New)
  }
  sides
}

///|
// Unit and root-list AST paths share all syntax calculation, mapping, and
// rendered-line validation. Their wrappers only restore filtered text.
fn ast_document_for_roots_with_budget(
  lhs_roots : ArrayView[@syntax.Syntax],
  rhs_roots : ArrayView[@syntax.Syntax],
  pipeline : DiffPipelineContext,
  reduce_sparse_replacements : Bool,
) -> AstBuildResult raise @computation.ScopeLimitExceeded {
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  match
    @diff.mark_syntax_roots_with_budget(
      lhs_roots,
      rhs_roots,
      change_map,
      pipeline.graph_limit,
      pipeline.budget,
    ) {
    WithinLimit(_) => ()
    GraphLimitExceeded => return AstGraphLimitExceeded
  }
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  let out_of_bounds_sides : Array[DiffSide] = []
  let lhs_positions = map_matched_positions(
    @syntax.change_positions_with_budget(lhs_roots, change_map, pipeline.budget),
    pipeline.old_view,
    pipeline.new_view,
    Old,
    New,
    out_of_bounds_sides,
  )
  let rhs_positions = map_matched_positions(
    @syntax.change_positions_with_budget(rhs_roots, change_map, pipeline.budget),
    pipeline.new_view,
    pipeline.old_view,
    New,
    Old,
    out_of_bounds_sides,
  )
  if !out_of_bounds_sides.is_empty() {
    let sides = ordered_out_of_bounds_sides(out_of_bounds_sides)
    return AstPositionsOutOfBounds(sides[:])
  }
  ast_document_from_positions(
    pipeline.old_view.lines(),
    pipeline.new_view.lines(),
    lhs_positions,
    rhs_positions,
    pipeline.context,
    reduce_sparse_replacements,
  )
}

///|
fn ast_unit_document_with_budget(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  pipeline : DiffPipelineContext,
  reduce_sparse_replacements : Bool,
) -> AstBuildResult raise @computation.ScopeLimitExceeded {
  let unit_pipeline = pipeline.with_views(
    unit_source_view(pipeline.old_view, old_unit),
    unit_source_view(pipeline.new_view, new_unit),
  )
  let lhs_roots : Array[@syntax.Syntax] = []
  let rhs_roots : Array[@syntax.Syntax] = []
  if old_unit is Some(unit) {
    lhs_roots.push(unit.root)
  }
  if new_unit is Some(unit) {
    rhs_roots.push(unit.root)
  }
  match
    ast_document_for_roots_with_budget(
      lhs_roots, rhs_roots, unit_pipeline, reduce_sparse_replacements,
    ) {
    AstDocument(document) =>
      AstDocument(
        @diff_ignore.restore_document(
          document,
          old=unit_pipeline.old_view,
          new=unit_pipeline.new_view,
        ),
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
    AstGraphLimitExceeded => AstGraphLimitExceeded
  }
}

///|
fn ast_root_document_with_budget(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  pipeline : DiffPipelineContext,
  reduce_sparse_replacements : Bool,
) -> AstBuildResult raise @computation.ScopeLimitExceeded {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  match
    ast_document_for_roots_with_budget(
      lhs_roots, rhs_roots, pipeline, reduce_sparse_replacements,
    ) {
    AstDocument(document) =>
      AstDocument(
        @diff_ignore.restore_document(
          document,
          old=pipeline.old_view,
          new=pipeline.new_view,
        ),
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
    AstGraphLimitExceeded => AstGraphLimitExceeded
  }
}
