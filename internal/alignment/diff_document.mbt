///|
/// The MoonBit-aware calculation engine used to build an aligned diff
/// document. Lexical mode retains token-level text changes inside the selected
/// whole-file or declaration-local fragments; AST mode reports only structural
/// changes.
pub(all) enum AlignedDiffMode {
  Lexical
  Ast
} derive(Eq)

///|
type DiffStatus = @model.DiffStatus

///|
type DiffSide = @model.DiffSide

///|
type ComputationStage = @model.ComputationStage

///|
type FallbackReason = @model.FallbackReason

///|
type DiffFragment = @model.DiffFragment

///|
type DiffSection = @model.DiffSection

///|
type DiffDocument = @model.DiffDocument

///|
/// Detailed renderer-neutral alignment output. Public callers consume this
/// through the `mbtdiff` facade.
pub(all) struct DetailedDiffResult {
  document : @model.DiffDocument
  status : @model.DiffStatus
} derive(Eq)

///|
priv struct DetailedUnitResult {
  document : @model.HunkDocument
  fallback : FallbackReason?
}

///|
priv enum AstBuildResult {
  AstDocument(@model.HunkDocument)
  AstPositionsOutOfBounds(ArrayView[DiffSide])
}

///|
type NovelRangeMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|
fn empty_document() -> @model.HunkDocument {
  { hunks: [], }
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
) -> @model.HunkDocument {
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
) -> @model.HunkDocument {
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
fn diff_fragment(
  document : @model.HunkDocument,
  fallback : FallbackReason?,
) -> DiffFragment {
  let fallbacks : Array[FallbackReason] = []
  if fallback is Some(reason) {
    fallbacks.push(reason)
  }
  { document, fallbacks: fallbacks[:], }
}

///|
fn whole_document(
  document : @model.HunkDocument,
  fallback? : FallbackReason,
) -> DiffDocument {
  @model.DiffDocument::Whole(diff_fragment(document, fallback))
}

///|
fn section_from_edit(edit : ImplEdit, diff : DiffFragment) -> DiffSection {
  match edit {
    Replace(old~, new~) =>
      @model.DiffSection::Matched(
        old=old.range,
        new=new.range,
        old_context=old.context,
        new_context=new.context,
        diff~,
      )
    Delete(old) =>
      @model.DiffSection::Deleted(old=old.range, old_context=old.context, diff~)
    Insert(new) =>
      @model.DiffSection::Inserted(
        new=new.range,
        new_context=new.context,
        diff~,
      )
  }
}

///|
fn top_level_result(
  plan : PerUnitPlan,
  fragments : Array[DiffFragment],
) -> DetailedDiffResult {
  let sections : Array[DiffSection] = []
  for index, edit in plan.edits {
    sections.push(section_from_edit(edit, fragments[index]))
  }
  let status : DiffStatus = if fragments.any(fragment => {
      !fragment.document.hunks.is_empty()
    }) {
    Changed
  } else if plan.reordered {
    Reordered
  } else {
    NoStructuralChanges
  }
  {
    document: @model.DiffDocument::TopLevel({
      sections: sections[:],
      old_order: plan.old_order[:],
      new_order: plan.new_order[:],
      reordered: plan.reordered,
    }),
    status,
  }
}

///|
fn lexical_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  ignore_comments : Bool,
) -> @model.HunkDocument {
  let old_local = unit_source_view(old_view, old_unit)
  let new_local = unit_source_view(new_view, new_unit)
  lexical_view_document(old_local, new_local, context, ignore_comments)
}

///|
fn complete_lexical_edit_context(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
) -> Int {
  @cmp.maximum(
    old_unit.map(unit => unit.range.len).unwrap_or(0),
    new_unit.map(unit => unit.range.len).unwrap_or(0),
  )
}

///|
// Per-unit lexical comparison is declaration-scoped by design. It compares
// only each unit's exact source slice and does not synthesize fragments for
// whitespace-only gaps before, between, or after units. RootList plans retain
// whole-file lexical behavior and therefore include those gaps. Changed
// declaration fragments use enough local context to cover both complete unit
// ranges; Whole comparisons and structural fallbacks retain caller context.
fn detailed_lexical_plan_document(
  plan : TopLevelPlan,
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
      { document: whole_document(document), status: Changed, }
    }
    PerUnit(unit_plan) => {
      let fragments : Array[DiffFragment] = []
      for edit in unit_plan.edits {
        let (old_unit, new_unit) = match edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let document = lexical_edit_document(
          old_unit,
          new_unit,
          old_view,
          new_view,
          complete_lexical_edit_context(old_unit, new_unit),
          ignore_comments,
        )
        fragments.push(diff_fragment(document, None))
      }
      top_level_result(unit_plan, fragments)
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
fn computation_stage(stage : @computation.Stage) -> ComputationStage {
  match stage {
    @computation.TopLevelAlignment => TopLevelAlignment
    @computation.SyntaxMatching => SyntaxMatching
    @computation.IntralineMatching => IntralineMatching
  }
}

///|
// Unit and root-list AST paths share all syntax calculation, mapping, and
// rendered-line validation. Their wrappers only restore filtered text.
fn ast_document_for_roots_with_budget(
  lhs_roots : ArrayView[@syntax.Syntax],
  rhs_roots : ArrayView[@syntax.Syntax],
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.ScopeBudget,
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
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.ScopeBudget,
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
        @diff_ignore.restore_document(document, old=old_local, new=new_local),
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
  }
}

///|
fn detailed_ast_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.ScopeBudget,
) -> DetailedUnitResult {
  let build = ast_unit_document_with_budget(
    old_unit,
    new_unit,
    old_view,
    new_view,
    context,
    graph_limit,
    !ignore_comments,
    budget,
  ) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) => {
      let reason : FallbackReason = ComputationLimitExceeded(
        stage=computation_stage(stage),
        limit~,
      )
      return {
        document: lexical_edit_document(
          old_unit, new_unit, old_view, new_view, context, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
    _ => {
      let reason : FallbackReason = GraphLimitExceeded(limit=graph_limit)
      return {
        document: lexical_edit_document(
          old_unit, new_unit, old_view, new_view, context, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
  }
  match build {
    AstDocument(document) => { document, fallback: None, }
    AstPositionsOutOfBounds(sides) => {
      let reason : FallbackReason = SyntaxPositionsOutOfBounds(sides~)
      {
        document: lexical_edit_document(
          old_unit, new_unit, old_view, new_view, context, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
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
  budget : @computation.ScopeBudget,
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
  let document = lexical_view_document(
    old_view, new_view, context, ignore_comments,
  )
  { document: whole_document(document, fallback=reason), status: Changed, }
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
  scope_limit : UInt,
) -> DetailedDiffResult {
  let budget = @computation.ScopeBudget::new(scope_limit)
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
    @computation.ScopeLimitExceeded(stage~, limit~) =>
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
        document: whole_document(document),
        status: if document.hunks.is_empty() {
          NoStructuralChanges
        } else {
          Changed
        },
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
  scope_limit : UInt,
) -> DetailedDiffResult {
  match plan {
    RootList(old~, new~) =>
      detailed_ast_root_list_document(
        old, new, old_view, new_view, context, graph_limit, ignore_comments, scope_limit,
      )
    PerUnit(unit_plan) => {
      let fragments : Array[DiffFragment] = []
      for edit in unit_plan.edits {
        let (old_unit, new_unit) = match edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let result = detailed_ast_edit_document(
          old_unit,
          new_unit,
          old_view,
          new_view,
          context,
          graph_limit,
          ignore_comments,
          @computation.ScopeBudget::new(scope_limit),
        )
        fragments.push(diff_fragment(result.document, result.fallback))
      }
      top_level_result(unit_plan, fragments)
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
fn calculate_diff_document_with_scope_limit(
  old_source : String,
  new_source : String,
  old_name : String,
  new_name : String,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  scope_limit : UInt,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  let context = @cmp.maximum(context, 0)
  if old_source == new_source {
    return { document: whole_document(empty_document()), status: Identical, }
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
    return { document: whole_document(document), status: IgnoredOnly, }
  }
  if parse_detail is Some(detail) {
    let document = if comment_document is Some(document) {
      document
    } else {
      lexical_source_document(old_source, new_source, context, false)
    }
    let reason : FallbackReason = ParseError(
      sides=parse_error_sides(old_reports, new_reports),
      detail~,
    )
    return {
      document: whole_document(document, fallback=reason),
      status: Changed,
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
    ignore_comments~,
  )
  let new_view = @diff_ignore.SourceView::from_source(
    new_source,
    ignored_ranges=new_collection.ignored_tests,
    ignore_comments~,
  )
  if ignore_comments || ignore_tests {
    let document = lexical_view_document(
      old_view, new_view, context, ignore_comments,
    )
    if document.hunks.is_empty() {
      return { document: whole_document(document), status: IgnoredOnly, }
    }
  }
  let budget = @computation.ScopeBudget::new(scope_limit)
  let plan = top_level_plan_impl(
    old_collection.units,
    new_collection.units,
    budget,
    ignore_uuid=ignore_comments,
  ) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        old_view,
        new_view,
        context,
        ignore_comments,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
  }
  match mode {
    Lexical =>
      detailed_lexical_plan_document(
        plan, old_view, new_view, context, ignore_comments,
      )
    Ast =>
      detailed_ast_plan_document(
        plan, old_view, new_view, context, graph_limit, ignore_comments, scope_limit,
      )
  }
}

///|
/// Calculate the sole renderer-neutral semantic document from one parse and
/// one top-level alignment plan. Reliable declaration pairings remain
/// section-local even when their two source orders cross. Section-local
/// lexical comparison returns each changed exact unit range in full, while
/// whitespace-only gaps outside those ranges are not represented as sections.
/// Caller context still controls Whole, AST, and AST-fallback documents.
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
) -> DetailedDiffResult {
  calculate_diff_document_with_scope_limit(
    old_source,
    new_source,
    old_name,
    new_name,
    context,
    graph_limit,
    ignore_comments,
    @computation.default_scope_limit(),
    ignore_tests~,
    mode~,
  )
}

///|
/// Calculate a renderer-neutral diff and typed fallback metadata. AST mode is
/// the default. The independently applied per-scope computation limit is
/// deliberately fixed as an implementation detail.
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
  )
}
