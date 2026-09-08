///|
fn open_comment_draft(model : Model, kind : DraftKind) -> (Model, Effects) {
  if !review_can_comment(model.review) || model.review.submission() is Some(_) {
    return (model, [])
  }
  if permission(model.review, OpenDraft(kind)) is Denied(message) {
    return (with_review(model, { ..model.review, notice: Some(message), }), [])
  }
  if model.review.draft() is Some(_) {
    return (model, [])
  }
  let sequence = model.review.draft_sequence + 1
  let draft = DraftData::{
    snapshot: model.review.context.snapshot,
    id: { generation: model.generation, sequence, },
    kind,
    body: "",
    error: None,
  }
  (
    with_review(model, {
      ..model.review,
      draft_sequence: sequence,
      notice: None,
      editor: Editing(draft),
    }),
    [],
  )
}

///|
fn owns_submission(
  model : Model,
  generation : Int,
  id : Int,
  stage : SubmissionPhase,
) -> Bool {
  match model.review.editor {
    Submitting(_, operation) =>
      owns_response(model.review, generation, id, operation.id) &&
      operation.generation == generation &&
      operation.phase == stage
    _ => false
  }
}

///|
fn owns_response(
  session : Session,
  generation : Int,
  id : Int,
  current : Int,
) -> Bool {
  generation == session.context.generation && id == current
}
