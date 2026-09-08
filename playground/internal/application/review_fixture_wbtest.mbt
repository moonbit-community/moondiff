///|
// Integration fixtures enter domain state through the same events as the UI.
fn fixture_event(
  review : Session,
  event : @comments.Event,
  view? : ChangeView = review_test_view(),
) -> Session {
  @comments.update(
    comment_session_context(review, {
      generation: 5,
      route: Some(view.reference),
      snapshot: Some({
        reference: view.reference,
        sha: view.sha,
        pull_snapshot: view.pull_snapshot,
      }),
      enabled: true,
    }),
    event,
  ).0
}

///|
fn review_fixture(
  original : Session,
  comments? : @comments.CommentsStatus,
  refresh? : @comments.CommentRefresh,
  snapshot_stale? : Bool,
  can_comment? : Bool,
  login? : String?,
  draft? : CommentDraft?,
  stage? : @comments.SubmissionPhase?,
  deletion? : @comments.CommentDeletion?,
  deleted? : Array[@comments.CommentId],
) -> Session {
  let base_view = review_test_view()
  let view = if stage == Some(Some(PostingCommit)) {
    {
      ..base_view,
      reference: @github.commit_reference("upstream", "project", base_view.sha),
    }
  } else {
    base_view
  }
  let dispatch = fn(review, event) { fixture_event(review, event, view~) }
  let mut review = original
  if can_comment is Some(_) || login is Some(_) {
    review = dispatch(
      review,
      Identity(
        can_comment.unwrap_or(review.can_comment),
        login.unwrap_or(review.login),
      ),
    )
  }
  if comments is Some(CommentsReady(bundle)) {
    review = dispatch(review, RefreshComments)
    if view.reference.target is PullRequest(_) {
      review = dispatch(
        review,
        CommentsMetadataLoaded(5, review.refresh_id, Ok(review_test_pull())),
      )
    }
    review = dispatch(review, CommentsLoaded(5, review.refresh_id, Ok(bundle)))
    if view.reference.target is PullRequest(_) {
      review = dispatch(
        review,
        CommentsValidated(5, review.refresh_id, Ok(review_test_pull())),
      )
    }
  } else if comments is Some(CommentsFailed(message)) {
    review = dispatch(review, RefreshComments)
    review = dispatch(
      review,
      CommentsMetadataLoaded(
        5,
        review.refresh_id,
        Err({ message, code: None, }),
      ),
    )
  }
  if draft is Some(value) {
    review = dispatch(review, CancelDraft)
    if value is Some(draft) {
      let saved_identity = (review.can_comment, review.login)
      review = dispatch(review, Identity(true, review.login))
      review = dispatch(
        review,
        match draft.kind {
          OverallDraft => OpenOverallDraft
          InlineDraft(index, anchor) => OpenInlineDraft(index, anchor)
          ReplyDraft(id) => OpenReplyDraft(id)
        },
      )
      review = dispatch(review, DraftBodyChanged(draft.body))
      review = dispatch(review, Identity(saved_identity.0, saved_identity.1))
    }
  }
  if stage is Some(Some(phase)) && review.submission() is None {
    review = dispatch(review, SubmitDraft)
    if phase is PostingReview &&
      review.draft() is Some({ kind: InlineDraft(_, anchor), .. }) {
      review = dispatch(
        review,
        CommentHeadChecked(
          5,
          review.submission_id,
          anchor,
          Ok(review_test_pull()),
        ),
      )
    }
  }
  if deleted is Some(ids) {
    for id in ids {
      review = dispatch(review, AskDelete(id))
      review = dispatch(review, ConfirmCommentDelete(id))
      review = dispatch(
        review,
        CommentDeleted(5, review.deletion_id, id, Ok({ deleted: true, })),
      )
    }
  }
  if deletion is Some(Some(state)) {
    let id = match state {
      ConfirmDelete(id) | Deleting(id) | DeleteFailed(id, _) => id
    }
    review = dispatch(review, AskDelete(id))
    if !(state is ConfirmDelete(_)) {
      review = dispatch(review, ConfirmCommentDelete(id))
    }
    if state is DeleteFailed(_, message) {
      review = dispatch(
        review,
        CommentDeleted(5, review.deletion_id, id, Err({ message, code: None, })),
      )
    }
  }
  if refresh is Some(RefreshList(Some(pull))) {
    review = dispatch(review, RefreshComments)
    review = dispatch(
      review,
      CommentsMetadataLoaded(5, review.refresh_id, Ok(pull)),
    )
  }
  if snapshot_stale == Some(true) {
    let pull = review_test_pull()
    review = dispatch(review, RefreshComments)
    review = dispatch(
      review,
      CommentsMetadataLoaded(
        5,
        review.refresh_id,
        Ok({ ..pull, head: { ..pull.head, sha: "changed", }, }),
      ),
    )
  }
  review
}

///|
fn review_state_with_draft(review : Session, draft : CommentDraft?) -> Session {
  review_fixture(review, draft~)
}

///|
fn review_state_with_comments(
  review : Session,
  comments : @comments.CommentsStatus,
) -> Session {
  review_fixture(review, comments~)
}
