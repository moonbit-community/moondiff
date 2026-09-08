///|
pub(all) enum Event {
  ContextChanged(Context)
  Reset(Bool, Bool)
  Identity(Bool, String?)
  RefreshComments
  BeginCommentsRefresh(Int, CommitRef)
  CommentsMetadataLoaded(Int, Int, Result[ApiPull, Failure])
  CommentsValidated(Int, Int, Result[ApiPull, Failure])
  AskDelete(CommentId)
  CancelDelete
  ConfirmCommentDelete(CommentId)
  CommentDeleted(Int, Int, CommentId, Result[DeleteResult, Failure])
  CommentsLoaded(Int, Int, Result[ApiCommentBundle, Failure])
  OpenOverallDraft
  OpenInlineDraft(Int, ReviewAnchor)
  OpenReplyDraft(Int64)
  DraftBodyChanged(String)
  CancelDraft
  SubmitDraft
  CommentHeadChecked(Int, Int, ReviewAnchor, Result[ApiPull, Failure])
  IssueCommentCreated(Int, Int, Result[ApiIssueComment, Failure])
  ReviewCommentCreated(Int, Int, Result[ApiReviewComment, Failure])
  CommitCommentCreated(Int, Int, Result[ApiCommitComment, Failure])
  ReviewReplyCreated(Int, Int, Result[ApiReviewComment, Failure])
}

///|
fn update_review(model : Model, msg : Event) -> (Model, Effects) {
  match msg {
    ContextChanged(_) => (model, [])
    Reset(enabled, preserve_draft) => {
      let initial = Session::new(enabled~)
      let review = {
        ..initial,
        context: model.review.context,
        can_comment: model.review.can_comment,
        login: model.review.login,
        editor: if preserve_draft {
          match model.review.editor {
            Editing(draft) => Editing(draft)
            _ => Empty
          }
        } else {
          Empty
        },
      }
      (with_review(model, review), [])
    }
    Identity(can_comment, login) =>
      (
        with_review(model, {
          ..model.review,
          can_comment,
          login,
          authentication_error: None,
        }),
        [],
      )
    AskDelete(id) => update_deletion(model, id, false)
    ConfirmCommentDelete(id) => update_deletion(model, id, true)
    CancelDelete =>
      if model.review.deletion is Some(Deleting(_)) {
        (model, [])
      } else {
        (with_review(model, { ..model.review, deletion: None, }), [])
      }
    CommentDeleted(generation, operation, id, result) =>
      finish_deletion(model, generation, operation, id, result)
    RefreshComments => begin_comments_refresh(model)
    BeginCommentsRefresh(generation, reference) => {
      guard generation == model.generation && model.route == Some(reference) else {
        return (model, [])
      }
      begin_comments_refresh(model)
    }
    CommentsMetadataLoaded(generation, id, result) => {
      guard owns_response(model.review, generation, id, model.review.refresh_id) &&
        model.review.refresh is RefreshMetadata &&
        model.route is Some(reference) else {
        return (model, [])
      }
      match result {
        Err(error) => (fail_comments_refresh(model, error), [])
        Ok(pull) if !matches_diff_snapshot(model, pull) =>
          (mark_snapshot_stale(model), [])
        Ok(pull) =>
          (
            with_review(model, {
              ..model.review,
              refresh: RefreshList(Some(pull)),
            }),
            comment_list_request(reference, generation, id),
          )
      }
    }
    CommentsValidated(generation, id, result) => {
      guard owns_response(model.review, generation, id, model.review.refresh_id) &&
        model.review.refresh is RefreshValidation(before, bundle) else {
        return (model, [])
      }
      match result {
        Err(error) => (fail_comments_refresh(model, error), [])
        Ok(after) if !same_pull_snapshot(before, after) ||
          !matches_diff_snapshot(model, after) =>
          (mark_snapshot_stale(model), [])
        Ok(_) => (accept_comments(model, bundle), [])
      }
    }
    CommentsLoaded(generation, id, result) => {
      guard owns_response(model.review, generation, id, model.review.refresh_id) &&
        model.review.refresh is RefreshList(before) else {
        return (model, [])
      }
      match result {
        Err(error) => (fail_comments_refresh(model, error), [])
        Ok(bundle) =>
          match before {
            None => (accept_comments(model, bundle), [])
            Some(pull) => {
              guard model.route is Some(reference) &&
                reference.target is PullRequest(number) else {
                return (model, [])
              }
              (
                with_review(model, {
                  ..model.review,
                  refresh: RefreshValidation(pull, copy_bundle(bundle)),
                }),
                raw_comment_head_request(reference, number, generation, result => {
                  CommentsValidated(generation, id, result)
                }),
              )
            }
          }
      }
    }
    OpenOverallDraft => open_comment_draft(model, OverallDraft)
    OpenInlineDraft(file_index, anchor) => {
      guard !model.review.snapshot_stale else { return (model, []) }
      open_comment_draft(model, InlineDraft(file_index, anchor))
    }
    OpenReplyDraft(comment_id) => {
      guard valid_reply_target(model.review, comment_id) else {
        return (model, [])
      }
      open_comment_draft(model, ReplyDraft(comment_id))
    }
    DraftBodyChanged(body) => {
      guard model.review.draft() is Some(draft) && !draft.submitting else {
        return (model, [])
      }
      let data = match model.review.editor {
        Editing(data) => data
        _ => return (model, [])
      }
      (
        with_review(model, {
          ..model.review,
          editor: Editing({ ..data, body, error: None, }),
        }),
        [],
      )
    }
    CancelDraft => {
      guard model.review.draft() is Some(draft) && !draft.submitting else {
        return (model, [])
      }
      (with_review(model, { ..model.review, notice: None, editor: Empty, }), [])
    }
    SubmitDraft => {
      guard model.review.draft() is Some(draft) &&
        !draft.submitting &&
        model.review.submission() is None &&
        model.phase is Showing(view) else {
        return (model, [])
      }
      if permission(model.review, Submit) is Denied(message) {
        return (update_draft(model, error=Some(message)), [])
      }
      let body = draft.body.trim().to_owned()
      let submission_id = model.review.submission_id + 1
      let stage : SubmissionPhase = match (view.reference.target, draft.kind) {
        (PullRequest(_), OverallDraft) => PostingIssue
        (PullRequest(_), InlineDraft(_, _)) => CheckingHead
        (PullRequest(_), ReplyDraft(_)) => PostingReply
        (Commit(_) | PullCommit(_, _), InlineDraft(_, _)) => PostingCommit
        _ => return (model, [])
      }
      let data = DraftData::{
        snapshot: draft.snapshot,
        id: draft.id,
        kind: draft.kind,
        body,
        error: None,
      }
      let operation = Operation::{
        generation: model.generation,
        id: submission_id,
        phase: stage,
        body,
      }
      let submitting = with_review(model, {
        ..model.review,
        submission_id,
        notice: None,
        published_url: None,
        editor: Submitting(data, operation),
      })
      let command = match (view.reference.target, draft.kind) {
        (PullRequest(number), OverallDraft) =>
          create_issue_comment_request(
            view.reference,
            number,
            body,
            model.generation,
            submission_id,
          )
        (PullRequest(number), InlineDraft(_, anchor)) =>
          comment_head_request(
            view.reference,
            number,
            anchor,
            model.generation,
            submission_id,
          )
        (Commit(sha), InlineDraft(_, anchor))
        | (PullCommit(_, sha), InlineDraft(_, anchor)) =>
          create_commit_comment_request(
            view.reference,
            sha,
            anchor,
            body,
            model.generation,
            submission_id,
          )
        (PullRequest(number), ReplyDraft(comment_id)) =>
          create_review_reply_request(
            view.reference,
            number,
            comment_id,
            body,
            model.generation,
            submission_id,
          )
        _ => []
      }
      (submitting, command)
    }
    CommentHeadChecked(generation, submission_id, anchor, result) => {
      if !owns_submission(model, generation, submission_id, CheckingHead) {
        return (model, [])
      }
      guard model.review.draft() is Some(draft) &&
        draft.kind is InlineDraft(_, selected) &&
        selected == anchor &&
        model.phase is Showing(view) &&
        view.reference.target is PullRequest(number) else {
        return (model, [])
      }
      match result {
        Err(error) => {
          let failed = update_draft(
            model,
            error=Some(comment_failure_message(error)),
          )
          (model_with_comment_auth_failure(failed, error), [])
        }
        Ok(pull) if model.review.snapshot_stale ||
          !matches_diff_snapshot(model, pull) =>
          (
            update_draft(
              mark_snapshot_stale(model),
              error=Some(
                "PR updated. Copy or cancel your draft before loading the latest snapshot.",
              ),
            ),
            [],
          )
        Ok(_) =>
          (
            with_review(model, {
              ..model.review,
              editor: match model.review.editor {
                Submitting(data, operation) =>
                  Submitting(data, { ..operation, phase: PostingReview, })
                other => other
              },
            }),
            create_review_comment_request(
              view.reference,
              number,
              view.sha,
              anchor,
              match model.review.editor {
                Submitting(_, operation) => operation.body
                _ => draft.body
              },
              generation,
              submission_id,
            ),
          )
      }
    }
    IssueCommentCreated(generation, submission_id, result) => {
      if !owns_submission(model, generation, submission_id, PostingIssue) {
        return (model, [])
      }
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
      )
    }
    ReviewCommentCreated(generation, submission_id, result) => {
      if !owns_submission(model, generation, submission_id, PostingReview) {
        return (model, [])
      }
      finish_comment_submission(
        match result {
          Ok(comment) =>
            with_review(
              model,
              merge_cache(model.review, PublishedReview(comment.html_url)),
            )
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
      )
    }
    CommitCommentCreated(generation, submission_id, result) => {
      if !owns_submission(model, generation, submission_id, PostingCommit) {
        return (model, [])
      }
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
      )
    }
    ReviewReplyCreated(generation, submission_id, result) => {
      if !owns_submission(model, generation, submission_id, PostingReply) {
        return (model, [])
      }
      finish_comment_submission(
        match result {
          Ok(comment) =>
            with_review(
              model,
              merge_cache(model.review, PublishedReview(comment.html_url)),
            )
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
      )
    }
  }
}
