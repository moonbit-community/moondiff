///|
test "overall input creates one draft with its first text and retains its identity" {
  let initial = pending_review_session(pending_empty_bundle())
  let (empty, effects) = update(initial, OverallDraftBodyChanged(""))
  assert_true(empty == initial)
  assert_true(effects.is_empty())
  let (first, effects) = update(initial, OverallDraftBodyChanged("中"))
  let draft = first.draft().unwrap()
  assert_true(draft.kind is OverallDraft)
  assert_eq(draft.body, "中")
  assert_true(initial.draft() is None)
  assert_true(effects.is_empty())
  let next = update(first, OverallDraftBodyChanged("中文评论")).0
  assert_eq(next.draft().unwrap().body, "中文评论")
  assert_true(next.draft().unwrap().id == draft.id)
  let cleared = update(next, OverallDraftBodyChanged("")).0
  assert_true(cleared.draft().unwrap().id == draft.id)
  assert_false(permission(cleared, Submit).allowed())
  let cancelled = update(cleared, CancelDraft).0
  assert_true(cancelled.draft() is None)
  let restarted = update(cancelled, OverallDraftBodyChanged("new draft")).0
  assert_true(restarted.draft().unwrap().id != draft.id)
}

///|
test "overall input cannot replace another draft or edit a submission" {
  let initial = pending_review_session({
    ..pending_empty_bundle(),
    review_comments: [review_comment_fixture(20)],
  })
  for event in [OpenInlineDraft(0, pending_anchor()), OpenReplyDraft(20L)] {
    let editing = update(update(initial, event).0, DraftBodyChanged("keep")).0
    let (unchanged, effects) = update(editing, OverallDraftBodyChanged("wrong"))
    assert_true(unchanged == editing)
    assert_true(effects.is_empty())
  }
  let posting = update(
      update(initial, OverallDraftBodyChanged("frozen")).0,
      SubmitDraft,
    ).0
  assert_true(posting.submission() is Some(PostingIssue))
  let (unchanged, effects) = update(posting, OverallDraftBodyChanged("wrong"))
  assert_true(unchanged == posting)
  assert_true(effects.is_empty())
}

///|
test "overall input stays local during a known identity check and cannot start anonymously" {
  let initial = pending_review_session(pending_empty_bundle())
  for
    session in [
      update(initial, Identity(false, None)).0,
      update(update(initial, Identity(false, None)).0, IdentityChecking).0,
      session_fixture(), // Commit pages have no overall comments.
    ] {
    assert_true(
      update(session, OverallDraftBodyChanged("blocked")).0.draft() is None,
    )
  }
  let checking = update(initial, IdentityChecking).0
  assert_true(permission(checking, OpenDraft(OverallDraft)).allowed())
  assert_true(checking.read_view().allowed(OpenDraft(OverallDraft)))
  let editing = update(checking, OverallDraftBodyChanged("during check")).0
  assert_eq(editing.draft().unwrap().body, "during check")
  assert_false(permission(editing, Submit).allowed())
  let expired = update(editing, Identity(false, None)).0
  let edited = update(expired, OverallDraftBodyChanged("retained offline")).0
  assert_eq(edited.draft().unwrap().body, "retained offline")
  assert_true(edited.draft().unwrap().id == editing.draft().unwrap().id)
  assert_false(permission(edited, Submit).allowed())
  let recovered = update(edited, Identity(true, Some("reviewer"))).0
  assert_true(permission(recovered, Submit).allowed())
}

///|
test "overall submission failure retains content and success clears the draft" {
  let editing = update(
      pending_review_session(pending_empty_bundle()),
      OverallDraftBodyChanged("first input"),
    ).0
  let posting = update(editing, SubmitDraft).0
  let failed = update(
      posting,
      IssueCommentCreated(
        7,
        posting.submission_id,
        Err({ message: "offline", code: None, }),
      ),
    ).0
  assert_eq(failed.draft().unwrap().body, "first input")
  assert_eq(failed.draft().unwrap().error, Some("offline"))
  assert_true(failed.draft().unwrap().id == editing.draft().unwrap().id)
  let edited = update(failed, OverallDraftBodyChanged("retry")).0
  assert_true(edited.draft().unwrap().error is None)
  let retrying = update(edited, SubmitDraft).0
  let published = update(
      retrying,
      IssueCommentCreated(
        7,
        retrying.submission_id,
        Ok({
          id: 91L,
          body: "retry",
          html_url: "https://github.com/comment/91",
          created_at: "today",
          user: Some({ login: "reviewer", }),
        }),
      ),
    ).0
  assert_true(published.draft() is None)
  assert_eq(published.overall_comments([]).issue_comments[0].body, "retry")
}
