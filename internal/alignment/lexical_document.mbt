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
fn lexical_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  pipeline : DiffPipelineContext,
  context : Int,
) -> @model.HunkDocument {
  let old_local = unit_source_view(pipeline.old_view, old_unit)
  let new_local = unit_source_view(pipeline.new_view, new_unit)
  lexical_view_document(old_local, new_local, context, pipeline.ignore_comments)
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
  pipeline : DiffPipelineContext,
) -> DetailedDiffResult {
  match plan {
    RootList(..) => {
      let document = lexical_view_document(
        pipeline.old_view,
        pipeline.new_view,
        pipeline.context,
        pipeline.ignore_comments,
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
          pipeline,
          complete_lexical_edit_context(old_unit, new_unit),
        )
        fragments.push(diff_fragment(document, None))
      }
      top_level_result(unit_plan, fragments)
    }
  }
}
