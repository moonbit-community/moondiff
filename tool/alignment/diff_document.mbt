///|
/// The MoonBit-aware calculation engine used to build an aligned diff
/// document. Lexical mode retains token-level text changes; AST mode reports
/// only structural changes.
pub(all) enum AlignedDiffMode {
  Lexical
  Ast
} derive(Eq)

///|
/// How an aligned document was produced.
pub(all) enum AlignedDiffOutcome {
  Rendered
  /// The whole document was rendered lexically because structural diffing
  /// could not be used.
  Fallback(String)
  /// Only the listed top-level edits were rendered lexically. All remaining
  /// edits still use the structural diff.
  PartialFallback(Array[String])
  NoStructuralChanges
  /// The inputs differ only in comments or blank lines excluded by the caller.
  NoNonCommentChanges
} derive(Eq)

///|
/// A renderer-neutral aligned diff and the outcome callers should present.
pub(all) struct AlignedDiffResult {
  document : @model.DiffDocument
  outcome : AlignedDiffOutcome
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
/// Detailed renderer-neutral alignment output. Public callers consume this
/// through the `mbtdiff` facade; the older public `AlignedDiffResult` type is
/// retained as a compatibility projection. `fallbacks` is a zero-copy
/// read-only view whose backing storage is never mutated after this result is
/// published.
pub(all) struct DetailedDiffResult {
  document : @model.DiffDocument
  status : DiffStatus
  fallbacks : ArrayView[FallbackInfo]
} derive(Eq)

///|
/// Renderer-neutral top-level section metadata used by compatibility
/// consumers that retain per-declaration file labels.
pub(all) struct DiffSection {
  old : LineRange?
  new : LineRange?
} derive(Eq)

///|
pub(all) enum DiffLayout {
  WholeDocument
  TopLevelSections(Array[DiffSection])
} derive(Eq)

///|
/// One shared calculation consumed by both the renderer-free facade and the
/// command-line compatibility renderer.
pub(all) struct DiffCalculation {
  result : DetailedDiffResult
  layout : DiffLayout
  parser_reason : String?
}

///|
priv struct UnitDocumentResult {
  document : @model.DiffDocument
  fallback_reason : String?
}

///|
priv struct DetailedUnitResult {
  document : @model.DiffDocument
  fallback : FallbackInfo?
  computation_exhausted : Bool
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
  context : Int,
  ignore_comments : Bool,
) -> @model.DiffDocument {
  lexical_source_document(
    source_slice(old_unit),
    source_slice(new_unit),
    context,
    ignore_comments,
  ).rebase(impl_line_base(old_unit) - 1, impl_line_base(new_unit) - 1)
}

///|
fn lexical_plan_document(
  plan : TopLevelPlan,
  old_source : String,
  new_source : String,
  context : Int,
  ignore_comments : Bool,
) -> AlignedDiffResult {
  match plan {
    RootList(..) => {
      let document = lexical_source_document(
        old_source, new_source, context, ignore_comments,
      )
      { document, outcome: Rendered }
    }
    PerUnit(edits) => {
      let hunks : Array[@model.DiffHunk] = []
      for edit in edits {
        let document = match edit {
          Replace(old~, new~) =>
            lexical_edit_document(
              Some(old),
              Some(new),
              context,
              ignore_comments,
            )
          Delete(old) =>
            lexical_edit_document(Some(old), None, context, ignore_comments)
          Insert(new) =>
            lexical_edit_document(None, Some(new), context, ignore_comments)
        }
        append_document(hunks, document)
      }
      if hunks.is_empty() && old_source != new_source {
        {
          document: lexical_source_document(
            old_source, new_source, context, ignore_comments,
          ),
          outcome: Fallback(
            "top-level reordering has no changes inside aligned declarations",
          ),
        }
      } else {
        { document: { hunks: hunks[:] }, outcome: Rendered }
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
  old_source : String,
  new_source : String,
  lhs_positions : ArrayView[MatchedPos],
  rhs_positions : ArrayView[MatchedPos],
  context : Int,
  reduce_sparse_replacements : Bool,
) -> @model.DiffDocument {
  let old_lines = document_lines(old_source)
  let new_lines = document_lines(new_source)
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
  { hunks: hunks[:] }
}

///|
fn graph_fallback_reason(
  graph_limit : UInt,
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
) -> String {
  let location = match (old_unit, new_unit) {
    (Some(old), Some(new)) =>
      "old line \{old.start_line}, new line \{new.start_line}"
    (Some(old), None) => "old line \{old.start_line}"
    (None, Some(new)) => "new line \{new.start_line}"
    (None, None) => "file"
  }
  "graph limit exceeded (\{graph_limit}) at \{location}"
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
      for edit in edits {
        sections.push(
          match edit {
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
      TopLevelSections(sections)
    }
  }
}

///|
fn ast_unit_document_with_budget(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> @model.DiffDocument raise {
  let old_source = source_slice(old_unit)
  let new_source = source_slice(new_unit)
  let old_offset = impl_line_base(old_unit) - 1
  let new_offset = impl_line_base(new_unit) - 1
  let lhs_roots : Array[@syntax.Syntax] = []
  let rhs_roots : Array[@syntax.Syntax] = []
  if old_unit is Some(unit) {
    lhs_roots.push(unit.root)
  }
  if new_unit is Some(unit) {
    rhs_roots.push(unit.root)
  }
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots_with_budget(
    lhs_roots, rhs_roots, change_map, graph_limit, budget,
  )
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  let lhs_positions = rebase_matched_positions(
    @syntax.change_positions_with_budget(lhs_roots, change_map, budget),
    old_offset,
    new_offset,
  )
  let rhs_positions = rebase_matched_positions(
    @syntax.change_positions_with_budget(rhs_roots, change_map, budget),
    new_offset,
    old_offset,
  )
  ast_document_from_positions(
    old_source, new_source, lhs_positions, rhs_positions, context, reduce_sparse_replacements,
  ).rebase(old_offset, new_offset)
}

///|
fn detailed_ast_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedUnitResult {
  let document = ast_unit_document_with_budget(
    old_unit,
    new_unit,
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
          old_unit, new_unit, context, ignore_comments,
        ),
        fallback: Some(unit_fallback(reason, old_unit, new_unit)),
        computation_exhausted: true,
      }
    }
    _ => {
      let reason : FallbackReason = GraphLimitExceeded(limit=graph_limit)
      return {
        document: lexical_edit_document(
          old_unit, new_unit, context, ignore_comments,
        ),
        fallback: Some(unit_fallback(reason, old_unit, new_unit)),
        computation_exhausted: false,
      }
    }
  }
  { document, fallback: None, computation_exhausted: false }
}

///|
fn lexical_detailed_unit(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  context : Int,
  ignore_comments : Bool,
  reason : FallbackReason,
) -> DetailedUnitResult {
  {
    document: lexical_edit_document(
      old_unit, new_unit, context, ignore_comments,
    ),
    fallback: Some(unit_fallback(reason, old_unit, new_unit)),
    computation_exhausted: true,
  }
}

///|
fn ast_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
) -> UnitDocumentResult {
  let old_source = source_slice(old_unit)
  let new_source = source_slice(new_unit)
  let old_offset = impl_line_base(old_unit) - 1
  let new_offset = impl_line_base(new_unit) - 1
  let lhs_roots = Array::new()
  let rhs_roots = Array::new()
  if old_unit is Some(unit) {
    lhs_roots.push(unit.root)
  }
  if new_unit is Some(unit) {
    rhs_roots.push(unit.root)
  }
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, graph_limit) catch {
    _ => {
      let reason = graph_fallback_reason(graph_limit, old_unit, new_unit)
      return {
        document: lexical_source_document(
          old_source, new_source, context, ignore_comments,
        ).rebase(old_offset, new_offset),
        fallback_reason: Some(reason),
      }
    }
  }
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  let lhs_positions = rebase_matched_positions(
    @syntax.change_positions(lhs_roots, change_map),
    old_offset,
    new_offset,
  )
  let rhs_positions = rebase_matched_positions(
    @syntax.change_positions(rhs_roots, change_map),
    new_offset,
    old_offset,
  )
  {
    document: ast_document_from_positions(
      old_source, new_source, lhs_positions, rhs_positions, context, false,
    ).rebase(old_offset, new_offset),
    fallback_reason: None,
  }
}

///|
fn ast_root_list_document(
  old_source : String,
  new_source : String,
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
) -> AlignedDiffResult {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, graph_limit) catch {
    _ => {
      let reason = "graph limit exceeded (\{graph_limit})"
      return {
        document: lexical_source_document(
          old_source, new_source, context, ignore_comments,
        ),
        outcome: Fallback(reason),
      }
    }
  }
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  let document = ast_document_from_positions(
    old_source,
    new_source,
    @syntax.change_positions(lhs_roots, change_map),
    @syntax.change_positions(rhs_roots, change_map),
    context,
    false,
  )
  {
    document,
    outcome: if document.hunks.is_empty() {
      NoStructuralChanges
    } else {
      Rendered
    },
  }
}

///|
fn ast_root_document_with_budget(
  old_source : String,
  new_source : String,
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  context : Int,
  graph_limit : UInt,
  reduce_sparse_replacements : Bool,
  budget : @computation.Budget,
) -> @model.DiffDocument raise {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots_with_budget(
    lhs_roots, rhs_roots, change_map, graph_limit, budget,
  )
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  ast_document_from_positions(
    old_source,
    new_source,
    @syntax.change_positions_with_budget(lhs_roots, change_map, budget),
    @syntax.change_positions_with_budget(rhs_roots, change_map, budget),
    context,
    reduce_sparse_replacements,
  )
}

///|
fn whole_file_fallback(
  old_source : String,
  new_source : String,
  context : Int,
  ignore_comments : Bool,
  reason : FallbackReason,
) -> DetailedDiffResult {
  {
    document: lexical_source_document(
      old_source, new_source, context, ignore_comments,
    ),
    status: Changed,
    fallbacks: [{ reason, scope: WholeFile }],
  }
}

///|
fn detailed_ast_root_list_document(
  old_source : String,
  new_source : String,
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedDiffResult {
  let document = ast_root_document_with_budget(
    old_source,
    new_source,
    old_units,
    new_units,
    context,
    graph_limit,
    !ignore_comments,
    budget,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        old_source,
        new_source,
        context,
        ignore_comments,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
    _ =>
      return whole_file_fallback(
        old_source,
        new_source,
        context,
        ignore_comments,
        GraphLimitExceeded(limit=graph_limit),
      )
  }
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

///|
fn detailed_ast_plan_document(
  plan : TopLevelPlan,
  old_source : String,
  new_source : String,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
  budget : @computation.Budget,
) -> DetailedDiffResult {
  match plan {
    RootList(old~, new~) =>
      detailed_ast_root_list_document(
        old_source, new_source, old, new, context, graph_limit, ignore_comments,
        budget,
      )
    PerUnit(edits) => {
      let hunks : Array[@model.DiffHunk] = []
      let fallbacks : Array[FallbackInfo] = []
      let exhausted_reason : Ref[FallbackReason?] = Ref(None)
      for edit in edits {
        let (old_unit, new_unit) = match edit {
          Replace(old~, new~) => (Some(old), Some(new))
          Delete(old) => (Some(old), None)
          Insert(new) => (None, Some(new))
        }
        let result = match exhausted_reason.val {
          Some(reason) =>
            lexical_detailed_unit(
              old_unit, new_unit, context, ignore_comments, reason,
            )
          None =>
            detailed_ast_edit_document(
              old_unit, new_unit, context, graph_limit, ignore_comments, budget,
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
fn ast_plan_document(
  plan : TopLevelPlan,
  old_source : String,
  new_source : String,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
) -> AlignedDiffResult {
  match plan {
    RootList(old~, new~) =>
      ast_root_list_document(
        old_source, new_source, old, new, context, graph_limit, ignore_comments,
      )
    PerUnit(edits) => {
      let hunks : Array[@model.DiffHunk] = []
      let fallback_reasons : Array[String] = []
      for edit in edits {
        let result = match edit {
          Replace(old~, new~) =>
            ast_edit_document(
              Some(old),
              Some(new),
              context,
              graph_limit,
              ignore_comments,
            )
          Delete(old) =>
            ast_edit_document(
              Some(old),
              None,
              context,
              graph_limit,
              ignore_comments,
            )
          Insert(new) =>
            ast_edit_document(
              None,
              Some(new),
              context,
              graph_limit,
              ignore_comments,
            )
        }
        append_document(hunks, result.document)
        if result.fallback_reason is Some(reason) {
          fallback_reasons.push(reason)
        }
      }
      let document : @model.DiffDocument = { hunks: hunks[:] }
      let outcome = if !fallback_reasons.is_empty() {
        PartialFallback(fallback_reasons)
      } else if document.hunks.is_empty() {
        NoStructuralChanges
      } else {
        Rendered
      }
      { document, outcome }
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
fn parser_fallback_reason(
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
fn initial_diff_document_result(
  old_source : String,
  new_source : String,
  mode : AlignedDiffMode,
  context : Int,
  ignore_comments : Bool,
) -> AlignedDiffResult? {
  if old_source == new_source {
    return Some({
      document: empty_document(),
      outcome: if mode is Ast {
        NoStructuralChanges
      } else {
        Rendered
      },
    })
  }
  if ignore_comments {
    let filtered = lexical_source_document(
      old_source, new_source, context, true,
    )
    if filtered.hunks.is_empty() {
      return Some({ document: filtered, outcome: NoNonCommentChanges })
    }
  }
  None
}

///|
fn diff_document_from_parsed_roots(
  old_source : String,
  new_source : String,
  old_root : @cst.CstNode,
  new_root : @cst.CstNode,
  mode : AlignedDiffMode,
  context : Int,
  graph_limit : UInt,
  ignore_comments : Bool,
) -> AlignedDiffResult {
  let old_units = collect_impl_units(old_source, old_root)
  let new_units = collect_impl_units(new_source, new_root)
  let plan = top_level_plan(old_units, new_units, ignore_uuid=ignore_comments)
  match mode {
    Lexical =>
      lexical_plan_document(
        plan, old_source, new_source, context, ignore_comments,
      )
    Ast => {
      let result = ast_plan_document(
        plan, old_source, new_source, context, graph_limit, ignore_comments,
      )
      if !ignore_comments {
        return result
      }
      let document = @tokdiff.ignore_comments(
        result.document,
        old=document_lines(old_source),
        new=document_lines(new_source),
      )
      {
        document,
        outcome: if document.hunks.is_empty() &&
          !(result.outcome is (Fallback(_) | PartialFallback(_))) {
          NoStructuralChanges
        } else {
          result.outcome
        },
      }
    }
  }
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
) -> DiffCalculation {
  let context = @cmp.maximum(context, 0)
  if old_source == new_source {
    return {
      result: { document: empty_document(), status: Identical, fallbacks: [] },
      layout: WholeDocument,
      parser_reason: None,
    }
  }
  let old_parse = @cst.parse_structure(old_source, name=old_name)
  let new_parse = @cst.parse_structure(new_source, name=new_name)
  let old_reports = old_parse.diagnostics_view()
  let new_reports = new_parse.diagnostics_view()
  let parser_reason = parser_fallback_reason(old_reports, new_reports)
  let ignored_document = if ignore_comments {
    Some(lexical_source_document(old_source, new_source, context, true))
  } else {
    None
  }
  if ignored_document is Some(document) && document.hunks.is_empty() {
    return {
      result: { document, status: IgnoredOnly, fallbacks: [] },
      layout: WholeDocument,
      parser_reason,
    }
  }
  if parser_reason is Some(detail) {
    return {
      result: {
        document: match ignored_document {
          Some(document) => document
          None =>
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
      parser_reason,
    }
  }
  let old_units = collect_impl_units(old_source, old_parse.root())
  let new_units = collect_impl_units(new_source, new_parse.root())
  let budget = @computation.Budget::new(computation_limit)
  let plan = top_level_plan_with_budget(
    old_units,
    new_units,
    budget,
    ignore_uuid=ignore_comments,
  ) catch {
    @computation.LimitExceeded(stage~, limit~) =>
      return {
        result: whole_file_fallback(
          old_source,
          new_source,
          context,
          ignore_comments,
          ComputationLimitExceeded(stage=computation_stage(stage), limit~),
        ),
        layout: WholeDocument,
        parser_reason,
      }
  }
  let layout = layout_from_top_level_plan(plan)
  let result = detailed_ast_plan_document(
    plan, old_source, new_source, context, graph_limit, ignore_comments, budget,
  )
  let result = if ignore_comments {
    let document = @tokdiff.ignore_comments(
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
  { result, layout, parser_reason }
}

///|
/// Calculate the AST-first renderer-neutral diff, its presentation layout,
/// and parser diagnostics from one parse and one top-level alignment plan.
pub fn calculate_diff_document(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
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
  )
}

///|
/// Calculate the AST-first renderer-neutral diff and typed fallback metadata.
/// The computation limit is deliberately fixed as an implementation detail.
pub fn diff_document_detailed(
  old_source : String,
  new_source : String,
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
) -> DetailedDiffResult {
  calculate_diff_document(
    old_source,
    new_source,
    context~,
    graph_limit~,
    ignore_comments~,
  ).result
}

///|
fn computation_stage_text(stage : ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level alignment"
    SyntaxMatching => "syntax matching"
    IntralineMatching => "intraline matching"
  }
}

///|
fn scope_location(scope : FallbackScope) -> String {
  match scope {
    WholeFile => ""
    Region(old~, new~) => {
      let parts : Array[String] = []
      if old is Some(range) {
        parts.push("old line \{range.start + 1}")
      }
      if new is Some(range) {
        parts.push("new line \{range.start + 1}")
      }
      if parts.is_empty() {
        "file"
      } else {
        parts.join(", ")
      }
    }
  }
}

///|
fn fallback_reason_text(fallback : FallbackInfo) -> String {
  match fallback.reason {
    ParseError(detail~, ..) => detail
    GraphLimitExceeded(limit~) => {
      let base = "graph limit exceeded (\{limit})"
      let location = scope_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
    ComputationLimitExceeded(stage~, limit~) => {
      let base = "computation limit exceeded (\{limit}) during \{computation_stage_text(stage)}"
      let location = scope_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
  }
}

///|
fn detailed_compat_result(result : DetailedDiffResult) -> AlignedDiffResult {
  let outcome = if result.fallbacks.is_empty() {
    match result.status {
      Identical | NoStructuralChanges => AlignedDiffOutcome::NoStructuralChanges
      IgnoredOnly => AlignedDiffOutcome::NoNonCommentChanges
      Changed => AlignedDiffOutcome::Rendered
    }
  } else if result.fallbacks.length() == 1 &&
    result.fallbacks[0].scope is WholeFile {
    Fallback(fallback_reason_text(result.fallbacks[0]))
  } else {
    PartialFallback(result.fallbacks.map(fallback_reason_text))
  }
  { document: result.document, outcome }
}

///|
/// Calculate a MoonBit-aware renderer-neutral diff using the same top-level
/// alignment plan as the terminal AST renderer.
pub fn diff_document(
  old_source : String,
  new_source : String,
  mode : AlignedDiffMode,
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
) -> AlignedDiffResult {
  if mode is Ast {
    return detailed_compat_result(
      diff_document_detailed(
        old_source,
        new_source,
        context~,
        graph_limit~,
        ignore_comments~,
      ),
    )
  }
  let context = @cmp.maximum(context, 0)
  if initial_diff_document_result(
      old_source, new_source, mode, context, ignore_comments,
    )
    is Some(result) {
    return result
  }
  let old_parse = @cst.parse_structure(old_source, name="old")
  let new_parse = @cst.parse_structure(new_source, name="new")
  if parser_fallback_reason(
      old_parse.diagnostics_view(),
      new_parse.diagnostics_view(),
    )
    is Some(reason) {
    return {
      document: lexical_source_document(
        old_source, new_source, context, ignore_comments,
      ),
      outcome: Fallback(reason),
    }
  }
  diff_document_from_parsed_roots(
    old_source,
    new_source,
    old_parse.root(),
    new_parse.root(),
    mode,
    context,
    graph_limit,
    ignore_comments,
  )
}
