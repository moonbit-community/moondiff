///|
test "interrupted submissions preserve editable drafts and reject every late operation stage" {
  let anchor : ReviewAnchor = {
    path: "src/main.mbt",
    line: 2,
    side: Right,
    position: Some(3),
  }
  let editing = update(
      update(session_fixture(), OpenInlineDraft(0, anchor)).0,
      DraftBodyChanged("preserved draft"),
    ).0
  let original = editing.draft().unwrap()
  let error : Failure = {
    message: "late error",
    code: Some("authentication_required"),
  }
  for
    stage in [
      CheckingHead,
      PostingIssue,
      PostingReview,
      PostingCommit,
      PostingReply,
    ] {
    let data = match editing.editor {
      Editing(data) => data
      _ => panic()
    }
    let pending = {
      ..editing,
      submission_id: 4,
      editor: Submitting(data, {
        generation: 7,
        id: 4,
        phase: stage,
        body: data.body,
      }),
    }
    let (recovered, effects) = update(pending, RecoverInterrupted)
    assert_true(effects.is_empty())
    assert_true(recovered.submission() is None)
    let draft = recovered.draft().unwrap()
    assert_false(draft.submitting)
    assert_eq(draft.body, original.body)
    assert_true(
      draft.id == original.id &&
      draft.kind == original.kind &&
      draft.snapshot == original.snapshot,
    )
    assert_eq(draft.error, Some(INTERRUPTED_REQUEST_MESSAGE))
    assert_eq(recovered.notice, Some(INTERRUPTED_REQUEST_MESSAGE))
    let late : Event = match stage {
      CheckingHead => CommentHeadChecked(7, 4, anchor, Err(error))
      PostingIssue => IssueCommentCreated(7, 4, Err(error))
      PostingReview => ReviewCommentCreated(7, 4, Err(error))
      PostingCommit => CommitCommentCreated(7, 4, Err(error))
      PostingReply => ReviewReplyCreated(7, 4, Err(error))
    }
    for model in [recovered, update(recovered, SubmitDraft).0] {
      let (ignored, effects) = update(model, late)
      assert_true(ignored == model)
      assert_true(effects.is_empty())
    }
    assert_eq(
      update(recovered, DraftBodyChanged("edited")).0.draft().unwrap().body,
      "edited",
    )
  }
}

///|
test "interrupted deletion and list refresh reject late success without losing the cache" {
  let bundle : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [review_comment_fixture(1)],
    commit_comments: [],
  }
  let initial = session_list(session_fixture(), bundle)
  let confirming = update(initial, AskDelete(ReviewComment(1L))).0
  let deleting = update(confirming, ConfirmCommentDelete(ReviewComment(1L))).0
  let pending = update(deleting, RefreshComments).0
  let (recovered, effects) = update(pending, RecoverInterrupted)
  assert_true(effects.is_empty())
  assert_true(
    recovered.deletion ==
    Some(DeleteFailed(ReviewComment(1L), INTERRUPTED_REQUEST_MESSAGE)),
  )
  assert_true(recovered.comments() == initial.comments())
  assert_true(recovered.refresh is RefreshIdle)
  let retry = update(recovered, ConfirmCommentDelete(ReviewComment(1L))).0
  for model in [recovered, retry] {
    for
      event in [
        CommentDeleted(
          7,
          pending.deletion_id,
          ReviewComment(1L),
          Ok({ deleted: true, }),
        ),
        CommentsLoaded(
          7,
          pending.refresh_id,
          Ok({ issue_comments: [], review_comments: [], commit_comments: [], }),
        ),
      ] {
      let (ignored, effects) = update(model, event)
      assert_true(ignored == model)
      assert_true(effects.is_empty())
    }
  }
  let unchanged = update(confirming, RecoverInterrupted).0
  assert_true(unchanged.deletion == confirming.deletion)
  assert_eq(unchanged.notice, confirming.notice)
}
