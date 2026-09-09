///|
fn update_draft(model : Model, error~ : String?) -> Model {
  let data = match model.review.editor {
    Editing(data) | Submitting(data, _) => data
    Empty => return model
  }
  with_review(model, { ..model.review, editor: Editing({ ..data, error, }), })
}

///|
fn model_with_comment_auth_failure(model : Model, error : Failure) -> Model {
  if error.code == Some("authentication_required") {
    with_review(model, {
      ..model.review,
      can_comment: false,
      authentication_error: Some(error.message),
    })
  } else {
    model
  }
}

///|
fn finish_comment_submission(
  model : Model,
  generation : Int,
  error : Failure?,
) -> (Model, Effects) {
  if generation != model.generation {
    return (model, [])
  }
  if error is Some(error) {
    let failed = update_draft(model, error=Some(comment_failure_message(error)))
    return (model_with_comment_auth_failure(failed, error), [])
  }
  guard model.route is Some(reference) else { return (model, []) }
  (
    with_review(model, {
      ..model.review,
      notice: Some("Comment published."),
      editor: Empty,
    }),
    comments_request(reference, generation),
  )
}

///|
fn insert_issue_comment(model : Model, comment : ApiIssueComment) -> Model {
  with_review(model, merge_cache(model.review, PublishedIssue(comment)))
}

///|
fn insert_commit_comment(model : Model, comment : ApiCommitComment) -> Model {
  with_review(model, merge_cache(model.review, PublishedCommit(comment)))
}
