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
  rows : ArrayView[@model.DiffRow]
  fallback : FallbackReason?
}

///|
priv enum AstBuildResult {
  AstRows(ArrayView[@model.DiffRow])
  AstPositionsOutOfBounds(ArrayView[DiffSide])
}

///|
type NovelRangeMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|
fn empty_rows() -> ArrayView[@model.DiffRow] {
  []
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
fn lexical_source_rows(
  old_source : String,
  new_source : String,
  ignore_comments : Bool,
) -> ArrayView[@model.DiffRow] {
  let old = document_lines(old_source)
  let new = document_lines(new_source)
  @tokdiff.diff_rows(old~, new~, line_cleanup=true, ignore_comments~)
}

///|
fn lexical_view_rows(
  old : SourceView,
  new : SourceView,
  ignore_comments : Bool,
) -> ArrayView[@model.DiffRow] {
  let rows = @tokdiff.diff_rows(
    old=old.lines(),
    new=new.lines(),
    line_cleanup=true,
    ignore_comments~,
  )
  if rows.is_empty() {
    []
  } else {
    @diff_ignore.restore_rows(rows, old~, new~)
  }
}

///|
fn diff_fragment(
  rows : ArrayView[@model.DiffRow],
  fallback : FallbackReason?,
) -> DiffFragment {
  let fallbacks : Array[FallbackReason] = []
  if fallback is Some(reason) {
    fallbacks.push(reason)
  }
  { rows, fallbacks: fallbacks[:] }
}

///|
fn whole_document(
  rows : ArrayView[@model.DiffRow],
  fallback? : FallbackReason,
) -> DiffDocument {
  @model.DiffDocument::Whole(diff_fragment(rows, fallback))
}

///|
fn section_from_edit(edit : ImplEdit, diff : DiffFragment) -> DiffSection {
  match edit {
    Replace(old~, new~) =>
      @model.DiffSection::Matched(old=old.range, new=new.range, diff~)
    Delete(old) => @model.DiffSection::Deleted(old=old.range, diff~)
    Insert(new) => @model.DiffSection::Inserted(new=new.range, diff~)
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
      !fragment.rows.is_empty()
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
fn lexical_edit_rows(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_view : SourceView,
  new_view : SourceView,
  ignore_comments : Bool,
) -> ArrayView[@model.DiffRow] {
  let old_local = unit_source_view(old_view, old_unit)
  let new_local = unit_source_view(new_view, new_unit)
  lexical_view_rows(old_local, new_local, ignore_comments)
}

///|
// Per-unit lexical comparison is declaration-scoped by design. It compares
// only each unit's exact source slice and does not synthesize fragments for
// whitespace-only gaps before, between, or after units. RootList plans retain
// whole-file lexical behavior and therefore include those gaps.
fn detailed_lexical_plan_document(
  plan : TopLevelPlan,
  old_view : SourceView,
  new_view : SourceView,
  ignore_comments : Bool,
) -> DetailedDiffResult {
  match plan {
    RootList(..) => {
      let rows = lexical_view_rows(old_view, new_view, ignore_comments)
      { document: whole_document(rows), status: Changed }
    }
    PerUnit(unit_plan) => {
      let fragments : Array[DiffFragment] = []
      for edit in unit_plan.edits {
        let rows = match edit {
          Replace(old~, new~) =>
            lexical_edit_rows(
              Some(old),
              Some(new),
              old_view,
              new_view,
              ignore_comments,
            )
          Delete(old) =>
            unit_source_view(old_view, Some(old)).changed_rows(true)
          Insert(new) =>
            unit_source_view(new_view, Some(new)).changed_rows(false)
        }
        fragments.push(diff_fragment(rows, None))
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
fn ast_line_is_novel(
  line : Int?,
  novel_lines : @line_alignment.LineSet,
) -> Bool {
  line is Some(line) && novel_lines.contains(line)
}

///|
fn ast_pair_is_changed(
  pair : (Int?, Int?),
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> Bool {
  ast_line_is_novel(pair.0, novel_lhs) || ast_line_is_novel(pair.1, novel_rhs)
}

///|
fn ast_line_pair(
  pair : (Int?, Int?),
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_ranges : NovelRangeMap,
  new_ranges : NovelRangeMap,
) -> @model.DiffLinePair {
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
fn ast_row(
  pair : (Int?, Int?),
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  old_ranges : NovelRangeMap,
  new_ranges : NovelRangeMap,
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> @model.DiffRow {
  if ast_pair_is_changed(pair, novel_lhs, novel_rhs) {
    Changed(ast_line_pair(pair, old_lines, new_lines, old_ranges, new_ranges))
  } else {
    match pair {
      (Some(old_line), Some(new_line)) if old_lines[old_line] ==
        new_lines[new_line] =>
        Context({
          old_index: old_line,
          new_index: new_line,
          text: old_lines[old_line],
        })
      _ =>
        Neutral(
          ast_line_pair(pair, old_lines, new_lines, old_ranges, new_ranges),
        )
    }
  }
}

///|
fn ast_pair_side_is_changed(
  line : Int?,
  opposite : Int?,
  novel_lines : @line_alignment.LineSet,
) -> Bool {
  ast_line_is_novel(line, novel_lines) || (line is Some(_) && opposite is None)
}

///|
fn ast_pair_affects_sparse_replacement(
  pair : (Int?, Int?),
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> Bool {
  ast_pair_side_is_changed(pair.0, pair.1, novel_lhs) ||
  ast_pair_side_is_changed(pair.1, pair.0, novel_rhs)
}

///|
fn ast_should_render_as_block_replacement(
  segment : ArrayView[(Int?, Int?)],
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> Bool {
  let lhs_lines : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let rhs_lines : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let mut all_present_sides_are_novel = true
  for pair in segment {
    let lhs_novel = ast_pair_side_is_changed(pair.0, pair.1, novel_lhs)
    let rhs_novel = ast_pair_side_is_changed(pair.1, pair.0, novel_rhs)
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
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> Unit {
  if ast_should_render_as_block_replacement(segment, novel_lhs, novel_rhs) {
    for pair in segment {
      if ast_pair_side_is_changed(pair.0, pair.1, novel_lhs) {
        output.push((pair.0, None))
      }
    }
    for pair in segment {
      if ast_pair_side_is_changed(pair.1, pair.0, novel_rhs) {
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
  novel_lhs : @line_alignment.LineSet,
  novel_rhs : @line_alignment.LineSet,
) -> Array[(Int?, Int?)] {
  let output : Array[(Int?, Int?)] = []
  let segment : Array[(Int?, Int?)] = []
  for pair in lines {
    if ast_pair_affects_sparse_replacement(pair, novel_lhs, novel_rhs) {
      segment.push(pair)
    } else {
      append_ast_segment_lines(output, segment, novel_lhs, novel_rhs)
      segment.clear()
      output.push(pair)
    }
  }
  append_ast_segment_lines(output, segment, novel_lhs, novel_rhs)
  output
}

///|
fn ast_rows_from_positions(
  old_lines : ArrayView[String],
  new_lines : ArrayView[String],
  lhs_positions : ArrayView[MatchedPos],
  rhs_positions : ArrayView[MatchedPos],
  reduce_sparse_replacements : Bool,
) -> AstBuildResult {
  let out_of_bounds = ast_position_out_of_bounds_sides(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  if !out_of_bounds.is_empty() {
    return AstPositionsOutOfBounds(out_of_bounds[:])
  }
  let (novel_lhs, novel_rhs) = @line_alignment.novel_line_sets(
    lhs_positions, rhs_positions,
  )
  if novel_lhs.is_empty() && novel_rhs.is_empty() {
    return AstRows([])
  }
  let aligned = @line_alignment.all_matched_lines_filled(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  let pairs = if reduce_sparse_replacements {
    reduce_ast_sparse_replacements(aligned, novel_lhs, novel_rhs)
  } else {
    aligned
  }
  let old_ranges = collect_novel_ranges(lhs_positions)
  let new_ranges = collect_novel_ranges(rhs_positions)
  let rows : Array[@model.DiffRow] = []
  for pair in pairs {
    rows.push(
      ast_row(
        pair, old_lines, new_lines, old_ranges, new_ranges, novel_lhs, novel_rhs,
      ),
    )
  }
  AstRows(rows[:])
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
fn ast_rows_for_roots_with_budget(
  lhs_roots : ArrayView[@syntax.Syntax],
  rhs_roots : ArrayView[@syntax.Syntax],
  old_view : SourceView,
  new_view : SourceView,
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
  ast_rows_from_positions(
    old_view.lines(),
    new_view.lines(),
    lhs_positions,
    rhs_positions,
    reduce_sparse_replacements,
  )
}

///|
fn ast_unit_rows_with_budget(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_view : SourceView,
  new_view : SourceView,
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
    ast_rows_for_roots_with_budget(
      lhs_roots, rhs_roots, old_local, new_local, graph_limit, reduce_sparse_replacements,
      budget,
    ) {
    AstRows(rows) =>
      AstRows(
        if rows.is_empty() {
          []
        } else {
          @diff_ignore.restore_rows(rows, old=old_local, new=new_local)
        },
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
  }
}

///|
fn detailed_ast_edit_rows(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  old_view : SourceView,
  new_view : SourceView,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedUnitResult {
  match (old_unit, new_unit) {
    (Some(old), None) =>
      return {
        rows: unit_source_view(old_view, Some(old)).changed_rows(true),
        fallback: None,
      }
    (None, Some(new)) =>
      return {
        rows: unit_source_view(new_view, Some(new)).changed_rows(false),
        fallback: None,
      }
    (None, None) => return { rows: [], fallback: None }
    _ => ()
  }
  let build = ast_unit_rows_with_budget(
    old_unit,
    new_unit,
    old_view,
    new_view,
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
        rows: lexical_edit_rows(
          old_unit, new_unit, old_view, new_view, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
    _ => {
      let reason : FallbackReason = GraphLimitExceeded(limit=graph_limit)
      return {
        rows: lexical_edit_rows(
          old_unit, new_unit, old_view, new_view, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
  }
  match build {
    AstRows(rows) => { rows, fallback: None }
    AstPositionsOutOfBounds(sides) => {
      let reason : FallbackReason = SyntaxPositionsOutOfBounds(sides~)
      {
        rows: lexical_edit_rows(
          old_unit, new_unit, old_view, new_view, ignore_comments,
        ),
        fallback: Some(reason),
      }
    }
  }
}

///|
fn ast_root_rows_with_budget(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_view : SourceView,
  new_view : SourceView,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> AstBuildResult raise {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  match
    ast_rows_for_roots_with_budget(
      lhs_roots, rhs_roots, old_view, new_view, graph_limit, reduce_sparse_replacements,
      budget,
    ) {
    AstRows(rows) =>
      AstRows(
        if rows.is_empty() {
          []
        } else {
          @diff_ignore.restore_rows(rows, old=old_view, new=new_view)
        },
      )
    AstPositionsOutOfBounds(sides) => AstPositionsOutOfBounds(sides)
  }
}

///|
fn whole_file_fallback(
  old_view : SourceView,
  new_view : SourceView,
  ignore_comments : Bool,
  reason : FallbackReason,
) -> DetailedDiffResult {
  let rows = lexical_view_rows(old_view, new_view, ignore_comments)
  { document: whole_document(rows, fallback=reason), status: Changed }
}

///|
fn detailed_ast_root_list_document(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_view : SourceView,
  new_view : SourceView,
  graph_limit : UInt,
  ignore_comments : Bool,
  computation_limit : UInt,
) -> DetailedDiffResult {
  let budget = @computation.Budget::new(computation_limit)
  let build = ast_root_rows_with_budget(
    old_units,
    new_units,
    old_view,
    new_view,
    graph_limit,
    !ignore_comments,
    budget,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        old_view,
        new_view,
        ignore_comments,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
    _ =>
      return whole_file_fallback(
        old_view,
        new_view,
        ignore_comments,
        GraphLimitExceeded(limit=graph_limit),
      )
  }
  match build {
    AstPositionsOutOfBounds(sides) =>
      whole_file_fallback(
        old_view,
        new_view,
        ignore_comments,
        SyntaxPositionsOutOfBounds(sides~),
      )
    AstRows(rows) =>
      {
        document: whole_document(rows),
        status: if rows.is_empty() {
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
  graph_limit : UInt,
  ignore_comments : Bool,
  computation_limit : UInt,
) -> DetailedDiffResult {
  match plan {
    RootList(old~, new~) =>
      detailed_ast_root_list_document(
        old, new, old_view, new_view, graph_limit, ignore_comments, computation_limit,
      )
    PerUnit(unit_plan) => {
      let fragments : Array[DiffFragment] = []
      for edit in unit_plan.edits {
        let (old_unit, new_unit) = match edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let result = detailed_ast_edit_rows(
          old_unit,
          new_unit,
          old_view,
          new_view,
          graph_limit,
          ignore_comments,
          @computation.Budget::new(computation_limit),
        )
        fragments.push(diff_fragment(result.rows, result.fallback))
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
fn calculate_diff_document_with_limit(
  old_source : String,
  new_source : String,
  old_name : String,
  new_name : String,
  graph_limit : UInt,
  ignore_comments : Bool,
  computation_limit : UInt,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  if old_source == new_source {
    return { document: whole_document(empty_rows()), status: Identical }
  }
  let old_parse = @cst.parse_structure(old_source, name=old_name)
  let new_parse = @cst.parse_structure(new_source, name=new_name)
  let old_reports = old_parse.diagnostics_view()
  let new_reports = new_parse.diagnostics_view()
  let parse_detail = parse_fallback_detail(old_reports, new_reports)
  let comment_rows = if ignore_comments {
    Some(lexical_source_rows(old_source, new_source, true))
  } else {
    None
  }
  if comment_rows is Some(rows) && rows.is_empty() {
    return { document: whole_document(rows), status: IgnoredOnly }
  }
  if parse_detail is Some(detail) {
    let rows = if comment_rows is Some(rows) {
      rows
    } else {
      lexical_source_rows(old_source, new_source, false)
    }
    let reason : FallbackReason = ParseError(
      sides=parse_error_sides(old_reports, new_reports),
      detail~,
    )
    return { document: whole_document(rows, fallback=reason), status: Changed }
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
    let rows = lexical_view_rows(old_view, new_view, ignore_comments)
    if rows.is_empty() {
      return { document: whole_document(rows), status: IgnoredOnly }
    }
  }
  let budget = @computation.Budget::new(computation_limit)
  let plan = top_level_plan_impl(
    old_collection.units,
    new_collection.units,
    budget,
    ignore_uuid=ignore_comments,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        old_view,
        new_view,
        ignore_comments,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
  }
  match mode {
    Lexical =>
      detailed_lexical_plan_document(plan, old_view, new_view, ignore_comments)
    Ast =>
      detailed_ast_plan_document(
        plan, old_view, new_view, graph_limit, ignore_comments, computation_limit,
      )
  }
}

///|
/// Calculate the sole renderer-neutral semantic document from one parse and
/// one top-level alignment plan. Reliable declaration pairings remain
/// section-local even when their two source orders cross. Section-local
/// lexical comparison is limited to exact unit ranges; whitespace-only gaps
/// outside those ranges are not represented as sections.
pub fn calculate_diff_document(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  calculate_diff_document_with_limit(
    old_source,
    new_source,
    old_name,
    new_name,
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
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  calculate_diff_document(
    old_source,
    new_source,
    graph_limit~,
    ignore_comments~,
    ignore_tests~,
    mode~,
  )
}
