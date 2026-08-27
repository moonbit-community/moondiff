///|
/// The MoonBit-aware calculation engine used to build an aligned diff
/// document. Lexical mode retains token-level text changes; AST mode reports
/// only structural changes.
pub(all) enum AlignedDiffMode {
  Lexical
  Ast
} derive(Eq)

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type DiffStatus = @model.DiffStatus

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type DiffSide = @model.DiffSide

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type ComputationStage = @model.ComputationStage

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type FallbackReason = @model.FallbackReason

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type LineRange = @model.LineRange

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type FallbackScope = @model.FallbackScope

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type FallbackInfo = @model.FallbackInfo

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type DiffSection = @model.DiffSection

///|
/// Compatibility alias for the public renderer-neutral model type.
pub type DiffLayout = @model.DiffLayout

///|
/// Detailed renderer-neutral alignment output. Public callers consume this
/// through the `mbtdiff` facade. `fallbacks` is a zero-copy read-only view whose
/// backing storage is never mutated after this result is published.
pub(all) struct DetailedDiffResult {
  document : @model.DiffDocument
  status : DiffStatus
  fallbacks : ArrayView[FallbackInfo]
} derive(Eq)

///|
/// One shared calculation consumed by the renderer-free facade and internal
/// alignment tests.
pub(all) struct DiffCalculation {
  result : DetailedDiffResult
  layout : DiffLayout
}

///|
priv struct DetailedUnitResult {
  document : @model.DiffDocument
  fallback : FallbackInfo?
  computation_exhausted : Bool
}

///|
priv enum AstBuildResult {
  AstDocument(@model.DiffDocument)
  AstPositionsOutOfBounds(ArrayView[DiffSide])
}

///|
type NovelRangeMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|
fn empty_document() -> @model.DiffDocument {
  { hunks: [] }
}

///|
fn document_lines(source : String) -> Array[String] {
  if source == "" {
    []
  } else {
    @source_text.split_lines(source)
  }
}

///|
fn lexical_source_document(
  old_source : String,
  new_source : String,
  context : Int,
  ignore_comments : Bool,
) -> @model.DiffDocument {
  let old = document_lines(old_source)
  let new = document_lines(new_source)
  @tokdiff.diff(old~, new~, context~, line_cleanup=true, ignore_comments~)
}

///|
fn lexical_view_document(
  old : SourceView,
  new : SourceView,
  context : Int,
  ignore_comments : Bool,
) -> @model.DiffDocument {
  @diff_ignore.restore_document(
    @tokdiff.diff(
      old=old.lines(),
      new=new.lines(),
      context~,
      line_cleanup=true,
      ignore_comments~,
    ),
    old~,
    new~,
  )
}

///|
fn append_document(
  hunks : Array[@model.DiffHunk],
  document : @model.DiffDocument,
) -> Unit {
  hunks.push_iter(document.hunks.iter())
}

///|
fn lexical_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_offset : Int,
  new_offset : Int,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  ignore_comments : Bool,
) -> @model.DiffDocument {
  let old_local = unit_source_view(old_view, old_unit)
  let new_local = unit_source_view(new_view, new_unit)
  lexical_view_document(old_local, new_local, context, ignore_comments).rebase(
    old_offset, new_offset,
  )
}

///|
fn detailed_lexical_plan_document(
  plan : TopLevelPlan,
  old_source : String,
  new_source : String,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  ignore_comments : Bool,
) -> DetailedDiffResult {
  match plan {
    RootList(..) => {
      let document = lexical_view_document(
        old_view, new_view, context, ignore_comments,
      )
      { document, status: Changed, fallbacks: [] }
    }
    PerUnit(edits) => {
      let hunks : Array[@model.DiffHunk] = []
      for positioned in edits {
        let (old_unit, new_unit) = match positioned.edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let document = lexical_edit_document(
          old_unit,
          new_unit,
          positioned.old_offset,
          positioned.new_offset,
          old_view,
          new_view,
          context,
          ignore_comments,
        )
        append_document(hunks, document)
      }
      if hunks.is_empty() && old_source != new_source {
        {
          document: lexical_view_document(
            old_view, new_view, context, ignore_comments,
          ),
          status: Changed,
          fallbacks: [{ reason: TopLevelReordering, scope: WholeFile }],
        }
      } else {
        { document: { hunks: hunks[:] }, status: Changed, fallbacks: [] }
      }
    }
  }
}

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
    segments[last] = { kind, text: previous.text + text }
  } else {
    segments.push({ kind, text })
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
  { index, segments: segments[:] }
}

///|
fn ast_pair_is_context(
  pair : (Int?, Int?),
  hunk : @hunks.AstHunk,
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
  hunk : @hunks.AstHunk,
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
      context_lines.push({ old_index, new_index, text: old_lines[old_index] })
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
fn ast_line_is_novel(line : Int?, novel_lines : @hunks.LineSet) -> Bool {
  line is Some(line) && novel_lines.contains(line)
}

///|
fn ast_pair_side_is_changed(
  line : Int?,
  opposite : Int?,
  novel_lines : @hunks.LineSet,
) -> Bool {
  ast_line_is_novel(line, novel_lines) || (line is Some(_) && opposite is None)
}

///|
fn ast_pair_has_change(pair : (Int?, Int?), hunk : @hunks.AstHunk) -> Bool {
  ast_pair_side_is_changed(pair.0, pair.1, hunk.novel_lhs) ||
  ast_pair_side_is_changed(pair.1, pair.0, hunk.novel_rhs)
}

///|
fn ast_should_render_as_block_replacement(
  segment : ArrayView[(Int?, Int?)],
  hunk : @hunks.AstHunk,
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
  hunk : @hunks.AstHunk,
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
  hunk : @hunks.AstHunk,
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
  let matched_lines = @hunks.all_matched_lines_filled(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  let ast_hunks = @hunks.merge_adjacent_hunks(
    @hunks.matched_pos_to_hunks(lhs_positions, rhs_positions),
    matched_lines,
    context,
  )
  let old_ranges = collect_novel_ranges(lhs_positions)
  let new_ranges = collect_novel_ranges(rhs_positions)
  let hunks : Array[@model.DiffHunk] = []
  for hunk in ast_hunks {
    let (start, end_) = @hunks.contextual_index_range_for_hunk(
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
  AstDocument({ hunks: hunks[:] })
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
fn computation_stage(stage : @computation.Stage) -> ComputationStage {
  match stage {
    @computation.TopLevelAlignment => TopLevelAlignment
    @computation.SyntaxMatching => SyntaxMatching
    @computation.IntralineMatching => IntralineMatching
  }
}

///|
fn unit_line_range(unit : ImplUnit?) -> LineRange? {
  if unit is Some(unit) {
    Some({
      start: unit.start_line - 1,
      len: document_lines(unit.source).length(),
    })
  } else {
    None
  }
}

///|
fn unit_fallback(
  reason : FallbackReason,
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
) -> FallbackInfo {
  {
    reason,
    scope: Region(old=unit_line_range(old_unit), new=unit_line_range(new_unit)),
  }
}

///|
fn layout_from_top_level_plan(plan : TopLevelPlan) -> DiffLayout {
  match plan {
    RootList(..) => WholeDocument
    PerUnit(edits) => {
      let sections : Array[DiffSection] = []
      for positioned in edits {
        sections.push(
          match positioned.edit {
            Replace(old~, new~) =>
              {
                old: unit_line_range(Some(old)),
                new: unit_line_range(Some(new)),
              }
            Delete(old) => { old: unit_line_range(Some(old)), new: None }
            Insert(new) => { old: None, new: unit_line_range(Some(new)) }
          },
        )
      }
      TopLevelSections(sections[:])
    }
  }
}

///|
// Unit and root-list AST paths share all syntax calculation, mapping, and
// rendered-line validation. Their wrappers only restore filters and rebase.
fn ast_document_for_roots_with_budget(
  lhs_roots : ArrayView[@syntax.Syntax],
  rhs_roots : ArrayView[@syntax.Syntax],
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> AstBuildResult raise {
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots_with_budget(
    lhs_roots, rhs_roots, change_map, graph_limit, budget,
  )
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  let out_of_bounds_sides : Array[DiffSide] = []
  let lhs_positions = map_matched_positions(
    @syntax.change_positions_with_budget(lhs_roots, change_map, budget),
    old_view,
    new_view,
    Old,
    New,
    out_of_bounds_sides,
  )
  let rhs_positions = map_matched_positions(
    @syntax.change_positions_with_budget(rhs_roots, change_map, budget),
    new_view,
    old_view,
    New,
    Old,
    out_of_bounds_sides,
  )
  if !out_of_bounds_sides.is_empty() {
    let sides = ordered_out_of_bounds_sides(out_of_bounds_sides)
    return AstPositionsOutOfBounds(sides[:])
  }
  ast_document_from_positions(
    old_view.lines(),
    new_view.lines(),
    lhs_positions,
    rhs_positions,
    context,
    reduce_sparse_replacements,
  )
}

///|
fn ast_unit_document_with_budget(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_offset : Int,
  new_offset : Int,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> AstBuildResult raise {
  let old_local = unit_source_view(old_view, old_unit)
  let new_local = unit_source_view(new_view, new_unit)
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
      lhs_roots, rhs_roots, old_local, new_local, context, graph_limit, reduce_sparse_replacements,
      budget,
    ) {
    AstDocument(document) =>
      AstDocument(
        @diff_ignore.restore_document(document, old=old_local, new=new_local).rebase(
          old_offset, new_offset,
        ),
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
  }
}

///|
fn detailed_ast_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_offset : Int,
  new_offset : Int,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedUnitResult {
  let build = ast_unit_document_with_budget(
    old_unit,
    new_unit,
    old_offset,
    new_offset,
    old_view,
    new_view,
    context,
    graph_limit,
    !ignore_comments,
    budget,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) => {
      let reason : FallbackReason = ComputationLimitExceeded(
        stage=computation_stage(stage),
        limit~,
      )
      return {
        document: lexical_edit_document(
          old_unit, new_unit, old_offset, new_offset, old_view, new_view, context,
          ignore_comments,
        ),
        fallback: Some(unit_fallback(reason, old_unit, new_unit)),
        computation_exhausted: true,
      }
    }
    _ => {
      let reason : FallbackReason = GraphLimitExceeded(limit=graph_limit)
      return {
        document: lexical_edit_document(
          old_unit, new_unit, old_offset, new_offset, old_view, new_view, context,
          ignore_comments,
        ),
        fallback: Some(unit_fallback(reason, old_unit, new_unit)),
        computation_exhausted: false,
      }
    }
  }
  match build {
    AstDocument(document) =>
      { document, fallback: None, computation_exhausted: false }
    AstPositionsOutOfBounds(sides) => {
      let reason : FallbackReason = SyntaxPositionsOutOfBounds(sides~)
      {
        document: lexical_edit_document(
          old_unit, new_unit, old_offset, new_offset, old_view, new_view, context,
          ignore_comments,
        ),
        fallback: Some(unit_fallback(reason, old_unit, new_unit)),
        // Position corruption is local to this declaration. Unlike a shared
        // budget exhaustion, it must not force later declarations to degrade.
        computation_exhausted: false,
      }
    }
  }
}

///|
fn lexical_detailed_unit(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_offset : Int,
  new_offset : Int,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  ignore_comments : Bool,
  reason : FallbackReason,
) -> DetailedUnitResult {
  {
    document: lexical_edit_document(
      old_unit, new_unit, old_offset, new_offset, old_view, new_view, context, ignore_comments,
    ),
    fallback: Some(unit_fallback(reason, old_unit, new_unit)),
    computation_exhausted: true,
  }
}

///|
fn ast_root_document_with_budget(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> AstBuildResult raise {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  match
    ast_document_for_roots_with_budget(
      lhs_roots, rhs_roots, old_view, new_view, context, graph_limit, reduce_sparse_replacements,
      budget,
    ) {
    AstDocument(document) =>
      AstDocument(
        @diff_ignore.restore_document(document, old=old_view, new=new_view),
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
  }
}

///|
fn whole_file_fallback(
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  ignore_comments : Bool,
  reason : FallbackReason,
) -> DetailedDiffResult {
  {
    document: lexical_view_document(
      old_view, new_view, context, ignore_comments,
    ),
    status: Changed,
    fallbacks: [{ reason, scope: WholeFile }],
  }
}

///|
fn detailed_ast_root_list_document(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedDiffResult {
  let build = ast_root_document_with_budget(
    old_units,
    new_units,
    old_view,
    new_view,
    context,
    graph_limit,
    !ignore_comments,
    budget,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        old_view,
        new_view,
        context,
        ignore_comments,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
    _ =>
      return whole_file_fallback(
        old_view,
        new_view,
        context,
        ignore_comments,
        GraphLimitExceeded(limit=graph_limit),
      )
  }
  match build {
    AstPositionsOutOfBounds(sides) =>
      whole_file_fallback(
        old_view,
        new_view,
        context,
        ignore_comments,
        SyntaxPositionsOutOfBounds(sides~),
      )
    AstDocument(document) =>
      {
        document,
        status: if document.hunks.is_empty() {
          NoStructuralChanges
        } else {
          Changed
        },
        fallbacks: [],
      }
  }
}

///|
fn detailed_ast_plan_document(
  plan : TopLevelPlan,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedDiffResult {
  match plan {
    RootList(old~, new~) =>
      detailed_ast_root_list_document(
        old, new, old_view, new_view, context, graph_limit, ignore_comments, budget,
      )
    PerUnit(edits) => {
      let hunks : Array[@model.DiffHunk] = []
      let fallbacks : Array[FallbackInfo] = []
      let exhausted_reason : Ref[FallbackReason?] = Ref(None)
      for positioned in edits {
        let (old_unit, new_unit) = match positioned.edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let result = if exhausted_reason.val is Some(reason) {
          lexical_detailed_unit(
            old_unit,
            new_unit,
            positioned.old_offset,
            positioned.new_offset,
            old_view,
            new_view,
            context,
            ignore_comments,
            reason,
          )
        } else {
          detailed_ast_edit_document(
            old_unit,
            new_unit,
            positioned.old_offset,
            positioned.new_offset,
            old_view,
            new_view,
            context,
            graph_limit,
            ignore_comments,
            budget,
          )
        }
        append_document(hunks, result.document)
        if result.fallback is Some(fallback) {
          fallbacks.push(fallback)
          if result.computation_exhausted && exhausted_reason.val is None {
            exhausted_reason.val = Some(fallback.reason)
          }
        }
      }
      let document : @model.DiffDocument = { hunks: hunks[:] }
      {
        document,
        status: if document.hunks.is_empty() {
          NoStructuralChanges
        } else {
          Changed
        },
        fallbacks: fallbacks[:],
      }
    }
  }
}

///|
fn parse_report_summary(
  side : String,
  reports : ArrayView[@basic.Report],
) -> String? {
  if reports.is_empty() {
    None
  } else if reports.length() == 1 {
    Some("\{side}: \{reports[0]}")
  } else {
    Some("\{side}: \{reports.length()} parse errors, first: \{reports[0]}")
  }
}

///|
fn parse_fallback_detail(
  old_reports : ArrayView[@basic.Report],
  new_reports : ArrayView[@basic.Report],
) -> String? {
  match
    (
      parse_report_summary("old", old_reports),
      parse_report_summary("new", new_reports),
    ) {
    (Some(old_reason), Some(new_reason)) => Some(old_reason + "; " + new_reason)
    (Some(reason), None) | (None, Some(reason)) => Some(reason)
    (None, None) => None
  }
}

///|
fn parse_error_sides(
  old_reports : ArrayView[@basic.Report],
  new_reports : ArrayView[@basic.Report],
) -> ArrayView[DiffSide] {
  let sides : Array[DiffSide] = []
  if !old_reports.is_empty() {
    sides.push(Old)
  }
  if !new_reports.is_empty() {
    sides.push(New)
  }
  sides[:]
}

///|
fn calculate_diff_document_with_limit(
  old_source : String,
  new_source : String,
  old_name : String,
  new_name : String,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  computation_limit : UInt,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DiffCalculation {
  let context = @cmp.maximum(context, 0)
  if old_source == new_source {
    return {
      result: { document: empty_document(), status: Identical, fallbacks: [] },
      layout: WholeDocument,
    }
  }
  let old_parse = @cst.parse_structure(old_source, name=old_name)
  let new_parse = @cst.parse_structure(new_source, name=new_name)
  let old_reports = old_parse.diagnostics_view()
  let new_reports = new_parse.diagnostics_view()
  let parse_detail = parse_fallback_detail(old_reports, new_reports)
  let comment_document = if ignore_comments {
    Some(lexical_source_document(old_source, new_source, context, true))
  } else {
    None
  }
  if comment_document is Some(document) && document.hunks.is_empty() {
    return {
      result: { document, status: IgnoredOnly, fallbacks: [] },
      layout: WholeDocument,
    }
  }
  if parse_detail is Some(detail) {
    return {
      result: {
        document: if comment_document is Some(document) {
          document
        } else {
          lexical_source_document(old_source, new_source, context, false)
        },
        status: Changed,
        fallbacks: [
          {
            reason: ParseError(
              sides=parse_error_sides(old_reports, new_reports),
              detail~,
            ),
            scope: WholeFile,
          },
        ],
      },
      layout: WholeDocument,
    }
  }
  let old_collection = collect_impl_units_detailed(
    old_source,
    old_parse.root(),
    ignore_tests,
  )
  let new_collection = collect_impl_units_detailed(
    new_source,
    new_parse.root(),
    ignore_tests,
  )
  let old_view = @diff_ignore.SourceView::from_source(
    old_source,
    ignored_ranges=old_collection.ignored_tests,
  )
  let new_view = @diff_ignore.SourceView::from_source(
    new_source,
    ignored_ranges=new_collection.ignored_tests,
  )
  if ignore_comments || ignore_tests {
    let document = lexical_view_document(
      old_view, new_view, context, ignore_comments,
    )
    if document.hunks.is_empty() {
      return {
        result: { document, status: IgnoredOnly, fallbacks: [] },
        layout: WholeDocument,
      }
    }
  }
  let budget = @computation.Budget::new(computation_limit)
  let plan = top_level_plan_impl(
    old_collection.units,
    new_collection.units,
    budget,
    old_file_line_count=document_lines(old_source).length(),
    new_file_line_count=document_lines(new_source).length(),
    ignore_uuid=ignore_comments,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return {
        result: whole_file_fallback(
          old_view,
          new_view,
          context,
          ignore_comments,
          ComputationLimitExceeded(stage=computation_stage(stage), limit~),
        ),
        layout: WholeDocument,
      }
  }
  let result = match mode {
    Lexical =>
      detailed_lexical_plan_document(
        plan, old_source, new_source, old_view, new_view, context, ignore_comments,
      )
    Ast =>
      detailed_ast_plan_document(
        plan, old_view, new_view, context, graph_limit, ignore_comments, budget,
      )
  }
  let result = if mode is Ast && ignore_comments {
    let document = @diff_ignore.ignore_comments(
      result.document,
      old=document_lines(old_source),
      new=document_lines(new_source),
    )
    {
      document,
      status: if document.hunks.is_empty() && result.fallbacks.is_empty() {
        NoStructuralChanges
      } else {
        result.status
      },
      fallbacks: result.fallbacks,
    }
  } else {
    result
  }
  let layout : DiffLayout = if result.fallbacks is [{ scope: WholeFile, .. }] {
    WholeDocument
  } else {
    layout_from_top_level_plan(plan)
  }
  { result, layout }
}

///|
/// Calculate a renderer-neutral diff and its presentation layout from one
/// parse and one top-level alignment plan. AST mode is the default; lexical
/// mode keeps token-level text changes while retaining declaration alignment
/// and the shared top-level computation budget. Parse diagnostics are carried
/// by `FallbackReason::ParseError.detail`.
pub fn calculate_diff_document(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DiffCalculation {
  calculate_diff_document_with_limit(
    old_source,
    new_source,
    old_name,
    new_name,
    context,
    graph_limit,
    ignore_comments,
    @computation.default_limit(),
    ignore_tests~,
    mode~,
  )
}

///|
/// Calculate a renderer-neutral diff and typed fallback metadata. AST mode is
/// the default. The computation limit is deliberately fixed as an
/// implementation detail.
pub fn diff_document_detailed(
  old_source : String,
  new_source : String,
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  calculate_diff_document(
    old_source,
    new_source,
    context~,
    graph_limit~,
    ignore_comments~,
    ignore_tests~,
    mode~,
  ).result
}
