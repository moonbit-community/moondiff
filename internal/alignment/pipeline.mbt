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
// Configuration and source views shared by one renderer-neutral diff pipeline.
// The budget belongs to the current calculation scope; `fresh_scope` keeps all
// other inputs but deliberately allocates independent mutable budget state.
priv struct DiffPipelineContext {
  old_view : SourceView
  new_view : SourceView
  context : Int
  graph_limit : UInt
  scope_limit : UInt
  ignore_comments : Bool
  budget : @computation.ScopeBudget
}

///|
fn DiffPipelineContext::new(
  old_view : SourceView,
  new_view : SourceView,
  context : Int,
  graph_limit : UInt,
  scope_limit : UInt,
  ignore_comments : Bool,
) -> Self {
  {
    old_view,
    new_view,
    context,
    graph_limit,
    scope_limit,
    ignore_comments,
    budget: @computation.ScopeBudget::new(scope_limit),
  }
}

///|
fn DiffPipelineContext::fresh_scope(self : Self) -> Self {
  {
    old_view: self.old_view,
    new_view: self.new_view,
    context: self.context,
    graph_limit: self.graph_limit,
    scope_limit: self.scope_limit,
    ignore_comments: self.ignore_comments,
    budget: @computation.ScopeBudget::new(self.scope_limit),
  }
}

///|
fn DiffPipelineContext::with_views(
  self : Self,
  old_view : SourceView,
  new_view : SourceView,
) -> Self {
  {
    old_view,
    new_view,
    context: self.context,
    graph_limit: self.graph_limit,
    scope_limit: self.scope_limit,
    ignore_comments: self.ignore_comments,
    budget: self.budget,
  }
}

///|
fn empty_document() -> @model.HunkDocument {
  { hunks: [], }
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
fn detailed_ast_plan_document(
  plan : TopLevelPlan,
  pipeline : DiffPipelineContext,
) -> DetailedDiffResult {
  match plan {
    RootList(old~, new~) =>
      detailed_ast_root_list_document(old, new, pipeline.fresh_scope())
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
          pipeline.fresh_scope(),
        )
        fragments.push(diff_fragment(result.document, result.fallback))
      }
      top_level_result(unit_plan, fragments)
    }
  }
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
  let pipeline = DiffPipelineContext::new(
    old_view, new_view, context, graph_limit, scope_limit, ignore_comments,
  )
  let plan = top_level_plan_impl(
    old_collection.units,
    new_collection.units,
    pipeline.budget,
    ignore_uuid=ignore_comments,
  ) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        pipeline,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
  }
  match mode {
    Lexical => detailed_lexical_plan_document(plan, pipeline)
    Ast => detailed_ast_plan_document(plan, pipeline)
  }
}
