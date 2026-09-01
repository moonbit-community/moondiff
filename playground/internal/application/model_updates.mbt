///|
fn with_phase(model : Model, phase : Phase) -> Model {
  { ..model, phase, }
}

///|
fn with_review(model : Model, review : ReviewState) -> Model {
  { ..model, review, }
}

///|
fn update_draft(
  model : Model,
  body? : String,
  submitting? : Bool,
  error? : String?,
) -> Model {
  guard model.review.draft is Some(draft) else { return model }
  with_review(
    model,
    review_state_with_draft(
      model.review,
      Some({
        kind: draft.kind,
        body: body.unwrap_or(draft.body),
        submitting: submitting.unwrap_or(draft.submitting),
        error: if error is Some(value) {
          value
        } else {
          draft.error
        },
      }),
    ),
  )
}

///|
fn model_with_comment_auth_failure(model : Model, error : Error) -> Model {
  match extension_error_code(error) {
    Some("authentication_required") =>
      with_review(
        model,
        review_state_with_auth(
          model.review,
          AuthFailed(comment_failure_message(error)),
        ),
      )
    _ => model
  }
}

///|
fn finish_comment_submission(
  model : Model,
  generation : Int,
  error : Error?,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if generation != model.generation {
    return (model, @rabbita.none)
  }
  if error is Some(error) {
    let failed = update_draft(
      model,
      submitting=false,
      error=Some(comment_failure_message(error)),
    )
    return (model_with_comment_auth_failure(failed, error), @rabbita.none)
  }
  guard model.route is Some(reference) else { return (model, @rabbita.none) }
  (
    with_review(model, {
      auth: model.review.auth,
      // Keep the object returned by GitHub visible while the authoritative
      // comment list refresh runs in the background.
      comments: model.review.comments,
      draft: None,
    }),
    @rabbita.batch([
      comments_request(reference, generation, emit),
      @comments.notify_github_page_command(),
    ]),
  )
}

///|
fn insert_issue_comment(model : Model, comment : ApiIssueComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.issue_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: comments,
        review_comments: bundle.review_comments,
        commit_comments: bundle.commit_comments,
      }),
    ),
  )
}

///|
fn insert_review_comment(model : Model, comment : ApiReviewComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.review_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: bundle.issue_comments,
        review_comments: comments,
        commit_comments: bundle.commit_comments,
      }),
    ),
  )
}

///|
fn insert_commit_comment(model : Model, comment : ApiCommitComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.commit_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: bundle.issue_comments,
        review_comments: bundle.review_comments,
        commit_comments: comments,
      }),
    ),
  )
}
