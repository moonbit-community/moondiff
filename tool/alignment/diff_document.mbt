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
  document : @tokdiff.DiffDocument
  outcome : AlignedDiffOutcome
} derive(Eq)

///|
priv struct UnitDocumentResult {
  document : @tokdiff.DiffDocument
  fallback_reason : String?
}

///|
type NovelRangeMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|
fn empty_document() -> @tokdiff.DiffDocument {
  { hunks: [] }
}

///|
fn document_lines(source : String) -> Array[String] {
  if source == "" {
    []
  } else {
    @render.split_lines(source)
  }
}

///|
fn lexical_source_document(
  old_source : String,
  new_source : String,
  context : Int,
  ignore_comments : Bool,
) -> @tokdiff.DiffDocument {
  let old = document_lines(old_source)
  let new = document_lines(new_source)
  @tokdiff.diff(old~, new~, context~, line_cleanup=true, ignore_comments~)
}

///|
fn append_document(
  hunks : Array[@tokdiff.DiffHunk],
  document : @tokdiff.DiffDocument,
) -> Unit {
  hunks.push_iter(document.hunks.iter())
}

///|
fn lexical_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  context : Int,
  ignore_comments : Bool,
) -> @tokdiff.DiffDocument {
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
      let hunks : Array[@tokdiff.DiffHunk] = []
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
        { document: { hunks, }, outcome: Rendered }
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
  segments : Array[@tokdiff.DiffSegment],
  kind : @tokdiff.DiffSegmentKind,
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
fn ast_line_segments(
  text : String,
  line_ranges : Array[(Int, Int)]?,
) -> Array[@tokdiff.DiffSegment] {
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
  let segments : Array[@tokdiff.DiffSegment] = []
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
) -> @tokdiff.DiffLine {
  { index, segments: ast_line_segments(text, ranges.get(index)) }
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
) -> @tokdiff.DiffRow {
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
) -> Array[@tokdiff.DiffBlock] {
  let blocks : Array[@tokdiff.DiffBlock] = []
  let context_lines : Array[@tokdiff.ContextLine] = []
  let change_rows : Array[@tokdiff.DiffRow] = []
  for pair in pairs {
    if ast_pair_is_context(pair, hunk, old_lines, new_lines) {
      if !change_rows.is_empty() {
        blocks.push(ChangeBlock(change_rows.copy()))
        change_rows.clear()
      }
      guard pair is (Some(old_index), Some(new_index)) else { panic() }
      context_lines.push({ old_index, new_index, text: old_lines[old_index] })
    } else {
      if !context_lines.is_empty() {
        blocks.push(ContextBlock(context_lines.copy()))
        context_lines.clear()
      }
      change_rows.push(
        ast_change_row(pair, old_lines, new_lines, old_ranges, new_ranges),
      )
    }
  }
  if !context_lines.is_empty() {
    blocks.push(ContextBlock(context_lines))
  }
  if !change_rows.is_empty() {
    blocks.push(ChangeBlock(change_rows))
  }
  blocks
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
fn ast_range_text(start : Int, len : Int) -> String {
  if len == 1 {
    (start + 1).to_string()
  } else if len == 0 {
    "\{start},0"
  } else {
    "\{start + 1},\{len}"
  }
}

///|
fn ast_hunk_header(
  old_start : Int,
  old_len : Int,
  new_start : Int,
  new_len : Int,
) -> String {
  "@@ -\{ast_range_text(old_start, old_len)} +\{ast_range_text(new_start, new_len)} @@"
}

///|
fn ast_document_from_positions(
  old_source : String,
  new_source : String,
  lhs_positions : ArrayView[MatchedPos],
  rhs_positions : ArrayView[MatchedPos],
  context : Int,
) -> @tokdiff.DiffDocument {
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
  let hunks : Array[@tokdiff.DiffHunk] = []
  for hunk in ast_hunks {
    let (start, end_) = @hunks.contextual_index_range_for_hunk(
      hunk,
      matched_lines,
      context + 1,
    )
    let pairs = matched_lines[start:end_]
    let (old_start, old_len) = ast_hunk_side_range(pairs, true)
    let (new_start, new_len) = ast_hunk_side_range(pairs, false)
    hunks.push({
      header: ast_hunk_header(old_start, old_len, new_start, new_len),
      old_start,
      old_len,
      new_start,
      new_len,
      blocks: ast_hunk_blocks(
        pairs, hunk, old_lines, new_lines, old_ranges, new_ranges,
      ),
    })
  }
  { hunks, }
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
      old_source, new_source, lhs_positions, rhs_positions, context,
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
      let hunks : Array[@tokdiff.DiffHunk] = []
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
      let document : @tokdiff.DiffDocument = { hunks, }
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
      let document = result.document.ignore_comments(
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
