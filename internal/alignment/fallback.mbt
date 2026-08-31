///|
fn computation_stage(stage : @computation.Stage) -> ComputationStage {
  match stage {
    @computation.TopLevelAlignment => TopLevelAlignment
    @computation.SyntaxMatching => SyntaxMatching
    @computation.IntralineMatching => IntralineMatching
  }
}

///|
fn detailed_ast_edit_document(
  old_unit : ImplUnit?,
  new_unit : ImplUnit?,
  pipeline : DiffPipelineContext,
) -> DetailedUnitResult {
  let build = ast_unit_document_with_budget(
    old_unit,
    new_unit,
    pipeline,
    !pipeline.ignore_comments,
  ) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) => {
      let reason : FallbackReason = ComputationLimitExceeded(
        stage=computation_stage(stage),
        limit~,
      )
      return {
        document: lexical_edit_document(
          old_unit,
          new_unit,
          pipeline,
          pipeline.context,
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
          old_unit,
          new_unit,
          pipeline,
          pipeline.context,
        ),
        fallback: Some(reason),
      }
    }
    AstGraphLimitExceeded => {
      let reason : FallbackReason = GraphLimitExceeded(
        limit=pipeline.graph_limit,
      )
      {
        document: lexical_edit_document(
          old_unit,
          new_unit,
          pipeline,
          pipeline.context,
        ),
        fallback: Some(reason),
      }
    }
  }
}

///|
fn whole_file_fallback(
  pipeline : DiffPipelineContext,
  reason : FallbackReason,
) -> DetailedDiffResult {
  let document = lexical_view_document(
    pipeline.old_view,
    pipeline.new_view,
    pipeline.context,
    pipeline.ignore_comments,
  )
  { document: whole_document(document, fallback=reason), status: Changed, }
}

///|
fn detailed_ast_root_list_document(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  pipeline : DiffPipelineContext,
) -> DetailedDiffResult {
  let build = ast_root_document_with_budget(
    old_units,
    new_units,
    pipeline,
    !pipeline.ignore_comments,
  ) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) =>
      return whole_file_fallback(
        pipeline,
        ComputationLimitExceeded(stage=computation_stage(stage), limit~),
      )
  }
  match build {
    AstPositionsOutOfBounds(sides) =>
      whole_file_fallback(pipeline, SyntaxPositionsOutOfBounds(sides~))
    AstDocument(document) =>
      {
        document: whole_document(document),
        status: if document.hunks.is_empty() {
          NoStructuralChanges
        } else {
          Changed
        },
      }
    AstGraphLimitExceeded =>
      whole_file_fallback(
        pipeline,
        GraphLimitExceeded(limit=pipeline.graph_limit),
      )
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
