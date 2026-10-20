///|
pub(all) enum ReviewMsg {
  Domain(@comments.Event)
  RefreshComments
  LoadLatestSnapshot
  BeginCommentsRefresh(Int32, CommitRef)
  CommentsMetadataLoaded(Int32, Int32, Result[ApiPull, Error])
  CommentsValidated(Int32, Int32, Result[ApiPull, Error])
  AskDelete(@comments.CommentId)
  CancelDelete
  ConfirmCommentDelete(@comments.CommentId)
  CommentDeleted(
    Int32,
    Int32,
    @comments.CommentId,
    Result[@protocol.DeleteResult, Error]
  )
  CommentsLoaded(Int32, Int32, Result[ApiCommentBundle, Error])
  PageReactivated
  OpenOverallDraft
  OpenInlineDraft(Int32, ReviewAnchor)
  OpenReplyDraft(Int64)
  DraftBodyChanged(String)
  CancelDraft
  SubmitDraft
  CommentHeadChecked(Int32, Int32, ReviewAnchor, Result[ApiPull, Error])
  IssueCommentCreated(Int32, Int32, Result[ApiIssueComment, Error])
  ReviewCommentCreated(Int32, Int32, Result[ApiReviewComment, Error])
  CommitCommentCreated(Int32, Int32, Result[ApiCommitComment, Error])
  ReviewReplyCreated(Int32, Int32, Result[ApiReviewComment, Error])
}

///|
fn domain_review(
  model : Model,
  event : @comments.Event,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let contextual = comment_session_context(model.review, comment_context(model))
  let (review, effects) = @comments.update(contextual, event)
  if @identity.same(review, contextual) && effects.is_empty() {
    return (model, @rabbita.none)
  }
  (
    with_review(model, review),
    @rabbita.batch(effects.map(effect => run_comment_effect(effect, emit))),
  )
}

///|
fn update_review(
  model : Model,
  msg : ReviewMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if model.route
    .map(reference => range_reference_parts(reference) is Some(_))
    .unwrap_or(false) &&
    !(msg is PageReactivated) {
    return (model, @rabbita.none)
  }
  let event : @comments.Event = match msg {
    Domain(event) => event
    LoadLatestSnapshot => {
      guard @comments.permission(model.review, LoadSnapshot).allowed() &&
        model.route is Some(reference) else {
        return (model, @rabbita.none)
      }
      if reference.target is PullRequest(_) &&
        (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) {
        if model.access.freshness is Checking {
          return (model, @rabbita.none)
        }
        return (
          {
            ..model,
            access: {
              ..model.access,
              freshness: Checking,
              preparing: None,
              reload_requested: true,
            },
          },
          shared_snapshot_request(
            reference,
            model.generation,
            emit,
            revalidate=true,
          ),
        )
      }
      return begin_change_load(model, reference, emit)
    }
    PageReactivated => {
      guard !(model.auth is DeviceCancelling(_, _)) &&
        !(model.auth is Authorizing({ phase: Starting, .. }, _)) &&
        !(model.auth is AuthChecking) else {
        return (model, @rabbita.none)
      }
      return (
        if model.auth is SignedIn(..) {
          with_review(
            { ..model, access: { ..model.access, identity_checking: true, }, },
            @comments.update(model.review, IdentityChecking).0,
          )
        } else {
          model
        },
        reactivation_auth_status_request(
          model.route,
          model.generation,
          model.auth_revision,
          emit,
        ),
      )
    }
    RefreshComments => RefreshComments
    CancelDelete => CancelDelete
    OpenOverallDraft => OpenOverallDraft
    CancelDraft => CancelDraft
    SubmitDraft => SubmitDraft
    BeginCommentsRefresh(generation, reference) =>
      BeginCommentsRefresh(generation, reference)
    AskDelete(id) => AskDelete(id)
    ConfirmCommentDelete(id) => ConfirmCommentDelete(id)
    OpenInlineDraft(index, anchor) => OpenInlineDraft(index, anchor)
    OpenReplyDraft(id) => OpenReplyDraft(id)
    DraftBodyChanged(body) => DraftBodyChanged(body)
    CommentsMetadataLoaded(generation, id, result) =>
      CommentsMetadataLoaded(generation, id, result.map_err(comment_failure))
    CommentsValidated(generation, id, result) =>
      CommentsValidated(generation, id, result.map_err(comment_failure))
    CommentDeleted(generation, operation, id, result) =>
      CommentDeleted(generation, operation, id, result.map_err(comment_failure))
    CommentsLoaded(generation, id, result) =>
      CommentsLoaded(generation, id, result.map_err(comment_failure))
    CommentHeadChecked(generation, id, anchor, result) =>
      CommentHeadChecked(
        generation,
        id,
        anchor,
        result.map_err(comment_failure),
      )
    IssueCommentCreated(generation, id, result) =>
      IssueCommentCreated(generation, id, result.map_err(comment_failure))
    ReviewCommentCreated(generation, id, result) =>
      ReviewCommentCreated(generation, id, result.map_err(comment_failure))
    CommitCommentCreated(generation, id, result) =>
      CommitCommentCreated(generation, id, result.map_err(comment_failure))
    ReviewReplyCreated(generation, id, result) =>
      ReviewReplyCreated(generation, id, result.map_err(comment_failure))
  }
  domain_review(model, event, emit)
}
