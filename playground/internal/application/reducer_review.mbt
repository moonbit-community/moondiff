///|
pub(all) enum ReviewMsg {
  RefreshComments
  CommentsLoaded(Int, Result[ApiCommentBundle, Error])
  PageReactivated
  OpenOverallDraft
  OpenInlineDraft(Int, ReviewAnchor)
  OpenReplyDraft(Int64)
  DraftBodyChanged(String)
  CancelDraft
  SubmitDraft
  CommentHeadChecked(Int, ReviewAnchor, Result[ApiPull, Error])
  IssueCommentCreated(Int, Result[ApiIssueComment, Error])
  ReviewCommentCreated(Int, Result[ApiReviewComment, Error])
  CommitCommentCreated(Int, Result[ApiCommitComment, Error])
  ReviewReplyCreated(Int, Result[ApiReviewComment, Error])
}

///|
fn update_review(
  model : Model,
  msg : ReviewMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    RefreshComments => {
      guard extension_host_enabled() && model.route is Some(reference) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_comments(model.review, CommentsLoading),
        ),
        comments_request(reference, model.generation, emit),
      )
    }
    PageReactivated => {
      guard extension_host_enabled() && model.route is Some(reference) else {
        return (model, @rabbita.none)
      }
      (
        model,
        reactivation_auth_status_request(reference, model.generation, emit),
      )
    }
    CommentsLoaded(generation, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      match result {
        Ok(bundle) =>
          (
            with_review(
              model,
              review_state_with_comments(model.review, CommentsReady(bundle)),
            ),
            @rabbita.none,
          )
        Err(error) => {
          let failed = with_review(
            model,
            review_state_with_comments(
              model.review,
              CommentsFailed(comment_failure_message(error)),
            ),
          )
          (model_with_comment_auth_failure(failed, error), @rabbita.none)
        }
      }
    }
    OpenOverallDraft => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: OverallDraft,
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    OpenInlineDraft(file_index, anchor) => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: InlineDraft(file_index, anchor),
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    OpenReplyDraft(comment_id) => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: ReplyDraft(comment_id),
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    DraftBodyChanged(body) => {
      guard model.review.draft is Some(draft) && !draft.submitting else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({ kind: draft.kind, body, submitting: false, error: None, }),
          ),
        ),
        @rabbita.none,
      )
    }
    CancelDraft => {
      guard model.review.draft is Some(draft) && !draft.submitting else {
        return (model, @rabbita.none)
      }
      (
        with_review(model, review_state_with_draft(model.review, None)),
        @rabbita.none,
      )
    }
    SubmitDraft => {
      guard model.review.draft is Some(draft) &&
        !draft.submitting &&
        model.phase is Showing(view) else {
        return (model, @rabbita.none)
      }
      guard review_can_comment(model.review) else {
        return (
          update_draft(
            model,
            submitting=false,
            error=Some("Sign in with GitHub before posting a comment."),
          ),
          @rabbita.none,
        )
      }
      let body = draft.body.trim().to_owned()
      if body.is_empty() {
        return (
          update_draft(
            model,
            submitting=false,
            error=Some("Enter a comment before posting."),
          ),
          @rabbita.none,
        )
      }
      let submitting = with_review(
        model,
        review_state_with_draft(
          model.review,
          Some({ kind: draft.kind, body, submitting: true, error: None, }),
        ),
      )
      let command = match (view.reference.target, draft.kind) {
        (PullRequest(number), OverallDraft) =>
          create_issue_comment_request(
            view.reference,
            number,
            body,
            model.generation,
            emit,
          )
        (PullRequest(number), InlineDraft(_, anchor)) =>
          comment_head_request(
            view.reference,
            number,
            anchor,
            model.generation,
            emit,
          )
        (Commit(sha), InlineDraft(_, anchor))
        | (PullCommit(_, sha), InlineDraft(_, anchor)) =>
          create_commit_comment_request(
            view.reference,
            sha,
            anchor,
            body,
            model.generation,
            emit,
          )
        (PullRequest(number), ReplyDraft(comment_id)) =>
          create_review_reply_request(
            view.reference,
            number,
            comment_id,
            body,
            model.generation,
            emit,
          )
        _ => @rabbita.none
      }
      (submitting, command)
    }
    CommentHeadChecked(generation, anchor, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.review.draft is Some(draft) &&
        draft.kind is InlineDraft(_, selected) &&
        selected == anchor &&
        model.phase is Showing(view) &&
        view.reference.target is PullRequest(number) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) => {
          let failed = update_draft(
            model,
            submitting=false,
            error=Some(comment_failure_message(error)),
          )
          (model_with_comment_auth_failure(failed, error), @rabbita.none)
        }
        Ok(pull) if pull.head.sha != view.sha => {
          let (refreshed, command) = begin_change_load(
            model,
            view.reference,
            emit,
          )
          (
            with_review(refreshed, {
              auth: model.review.auth,
              comments: CommentsLoading,
              draft: Some({
                kind: draft.kind,
                body: draft.body,
                submitting: false,
                error: Some(
                  "The pull request head changed. Moondiff refreshed the snapshot; review the new diff before retrying.",
                ),
              }),
            }),
            command,
          )
        }
        Ok(_) =>
          (
            model,
            create_review_comment_request(
              view.reference,
              number,
              view.sha,
              anchor,
              draft.body,
              generation,
              emit,
            ),
          )
      }
    }
    IssueCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_issue_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    ReviewCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_review_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    CommitCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_commit_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    ReviewReplyCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_review_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
  }
}
