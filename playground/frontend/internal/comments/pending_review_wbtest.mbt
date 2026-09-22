///|
fn pending_review_pull() -> ApiPull {
  {
    title: "Pull request",
    html_url: "https://github.com/upstream/project/pull/17",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "upstream/project", }),
    },
    head: {
      sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repo: Some({ full_name: "contributor/project-fork", }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
}

///|
fn pending_empty_bundle() -> ApiCommentBundle {
  { issue_comments: [], review_comments: [], commit_comments: [], }
}

///|
fn pending_review_session(bundle : ApiCommentBundle) -> Session {
  let base = review_test_view()
  let pull = pending_review_pull()
  let view = { ..base, pull_snapshot: Some(pull), }
  let session = update(
      Session::new(enabled=true),
      ContextChanged({
        generation: 7,
        route: Some(view.reference),
        snapshot: Some({
          reference: view.reference,
          sha: view.sha,
          pull_snapshot: Some(pull),
        }),
        enabled: true,
      }),
    ).0
  let session = update(session, Identity(true, Some("reviewer"))).0
  pending_verified_refresh(session, bundle)
}

///|
fn pending_verified_refresh(
  session : Session,
  bundle : ApiCommentBundle,
) -> Session {
  let pull = pending_review_pull()
  let metadata = update(session, RefreshComments).0
  let id = metadata.refresh_id
  let listed = update(metadata, CommentsMetadataLoaded(7, id, Ok(pull))).0
  let validating = update(listed, CommentsLoaded(7, id, Ok(bundle))).0
  update(validating, CommentsValidated(7, id, Ok(pull))).0
}

///|
fn pending_anchor() -> ReviewAnchor {
  { path: "src/main.mbt", side: Right, line: 2, position: Some(3), }
}

///|
fn publish_inline_receipt(
  session : Session,
  id : Int,
  body : String,
) -> (Session, ApiReviewComment, Int) {
  let anchor = pending_anchor()
  let editing = update(session, OpenInlineDraft(0, anchor)).0
  let checking = update(update(editing, DraftBodyChanged(body)).0, SubmitDraft).0
  let operation = checking.submission_id
  let posting = update(
      checking,
      CommentHeadChecked(7, operation, anchor, Ok(pending_review_pull())),
    ).0
  let comment = {
    ..review_comment_fixture(id),
    body,
    html_url: "https://github.com/comment/\{id}",
  }
  (
    update(posting, ReviewCommentCreated(7, operation, Ok(comment))).0,
    comment,
    operation,
  )
}

///|
test "published reviews keep one frozen editor and consume the write response before synchronization" {
  let initial = pending_review_session(pending_empty_bundle())
  let (first, first_comment, first_operation) = publish_inline_receipt(
    initial, 50, "secret first body",
  )
  let draft = first.draft().unwrap()
  assert_true(draft.submitting)
  assert_eq(draft.body, "secret first body")
  assert_true(first.submission() == Some(SyncingReview(first_comment.id)))
  let first_view = first.read_view(path="src/main.mbt")
  assert_eq(first_view.pending_review_receipts.length(), 1)
  let receipt = first_view.pending_review_receipts[0]
  assert_eq(receipt.id, 50L)
  assert_eq(receipt.url, first_comment.html_url)
  assert_true(receipt.kind == InlineDraft(0, pending_anchor()))
  assert_eq(receipt.path, "src/main.mbt")
  assert_eq(receipt.generation, 7)
  assert_true(receipt.status is ReceiptSyncing)
  assert_eq(receipt.key(), "7:review:50")
  assert_eq(first.published_url, Some(first_comment.html_url))
  assert_eq(first.notice, None)

  for
    event in [
      SubmitDraft,
      CancelDraft,
      DraftBodyChanged("cannot change published text"),
      OpenOverallDraft,
      OpenInlineDraft(0, pending_anchor()),
    ] {
    let (blocked, effects) = update(first, event)
    assert_true(blocked == first)
    assert_true(effects.is_empty())
  }
  assert_false(permission(first, Submit).allowed())
  assert_false(permission(first, OpenDraft(OverallDraft)).allowed())

  let duplicate = merge_cache(first, PublishedReview(receipt))
  assert_eq(
    duplicate.read_view(path="src/main.mbt").pending_review_receipts.length(),
    1,
  )
  let (late, effects) = update(
    first,
    ReviewCommentCreated(7, first_operation, Ok(first_comment)),
  )
  assert_true(late == first)
  assert_true(effects.is_empty())

  let (failed_late, effects) = update(
    first,
    ReviewCommentCreated(
      7,
      first_operation,
      Err({ message: "late failure", code: None, }),
    ),
  )
  assert_true(failed_late == first)
  assert_true(effects.is_empty())

  let reset = update(first, Reset(true, false)).0
  assert_true(reset.draft() is None)
  assert_true(
    reset.read_view(path="src/main.mbt").pending_review_receipts.is_empty(),
  )
}

///|
test "review receipt refresh lifecycle waits, retries, fails, detects PR changes and confirms atomically" {
  let initial = pending_review_session(pending_empty_bundle())
  let (published, comment, _) = publish_inline_receipt(initial, 60, "body")
  let reference = review_test_view().reference

  let syncing = update(published, BeginCommentsRefresh(7, reference)).0
  assert_true(
    syncing.read_view(path="src/main.mbt").pending_review_receipts[0].status
    is ReceiptSyncing,
  )
  let id = syncing.refresh_id
  let listed = update(
      syncing,
      CommentsMetadataLoaded(7, id, Ok(pending_review_pull())),
    ).0
  let validating = update(
      listed,
      CommentsLoaded(7, id, Ok(pending_empty_bundle())),
    ).0
  let waiting = update(
      validating,
      CommentsValidated(7, id, Ok(pending_review_pull())),
    ).0
  let waiting_view = waiting.read_view(path="src/main.mbt")
  assert_true(waiting_view.pending_review_receipts[0].status is ReceiptWaiting)
  assert_true(waiting_view.group.review_comments.is_empty())
  assert_true(waiting.draft().unwrap().submitting)
  assert_true(waiting.draft().unwrap().id == published.draft().unwrap().id)

  let retry = update(waiting, RefreshComments).0
  assert_true(
    retry.read_view(path="src/main.mbt").pending_review_receipts[0].status
    is ReceiptSyncing,
  )
  let failed = update(
      retry,
      CommentsMetadataLoaded(
        7,
        retry.refresh_id,
        Err({ message: "offline", code: None, }),
      ),
    ).0
  assert_true(
    failed.read_view(path="src/main.mbt").pending_review_receipts[0].status
    is ReceiptSyncFailed,
  )
  assert_true(failed.draft().unwrap().submitting)
  assert_true(failed.draft().unwrap().error is Some(_))
  assert_false(permission(failed, Submit).allowed())
  let interrupted = update(published, RecoverInterrupted).0
  assert_true(
    interrupted.read_view(path="src/main.mbt").pending_review_receipts[0].status
    is ReceiptSyncFailed,
  )
  assert_true(interrupted.draft().unwrap().submitting)
  assert_eq(interrupted.draft().unwrap().body, "body")
  assert_false(permission(interrupted, Submit).allowed())
  assert_true(
    pending_verified_refresh(interrupted, {
      ..pending_empty_bundle(),
      review_comments: [comment],
    }).draft()
    is None,
  )

  let changed_refresh = update(waiting, RefreshComments).0
  let changed_pull = {
    ..pending_review_pull(),
    head: { ..pending_review_pull().head, sha: "changed", },
  }
  let changed = update(
      changed_refresh,
      CommentsMetadataLoaded(7, changed_refresh.refresh_id, Ok(changed_pull)),
    ).0
  assert_true(changed.snapshot_stale)
  assert_true(
    changed.read_view(path="src/main.mbt").pending_review_receipts[0].status
    is ReceiptPrChanged,
  )
  assert_true(changed.draft().unwrap().submitting)
  assert_true(permission(changed, LoadSnapshot).allowed())

  let confirming = update(waiting, RefreshComments).0
  let confirm_id = confirming.refresh_id
  let confirming = update(
      confirming,
      CommentsMetadataLoaded(7, confirm_id, Ok(pending_review_pull())),
    ).0
  let confirming = update(
      confirming,
      CommentsLoaded(
        7,
        confirm_id,
        Ok({ ..pending_empty_bundle(), review_comments: [comment], }),
      ),
    ).0
  let before_validation = confirming.read_view(path="src/main.mbt")
  assert_eq(before_validation.pending_review_receipts.length(), 1)
  assert_true(before_validation.group.review_comments.is_empty())
  assert_true(before_validation.draft().unwrap().submitting)
  let confirmed = update(
      confirming,
      CommentsValidated(7, confirm_id, Ok(pending_review_pull())),
    ).0
  let confirmed_view = confirmed.read_view(path="src/main.mbt")
  assert_true(confirmed_view.pending_review_receipts.is_empty())
  assert_true(confirmed.draft() is None)
  assert_true(confirmed.submission() is None)
  assert_eq(confirmed.notice, Some("Comment published."))
  assert_true(permission(confirmed, OpenDraft(OverallDraft)).allowed())
  assert_eq(confirmed_view.group.review_comments.map(c => c.id), [comment.id])
  assert_eq(
    waiting_view.pending_review_receipts[0].key(),
    confirmed_view.comment_key(ReviewComment(comment.id)),
  )
}

///|
test "reply receipts retain the original thread path after the root disappears" {
  let root = { ..review_comment_fixture(1), path: "original.mbt", }
  let initial = pending_review_session({
    ..pending_empty_bundle(),
    review_comments: [root],
  })
  let editing = update(initial, OpenReplyDraft(root.id)).0
  let posting = update(
      update(editing, DraftBodyChanged("reply body")).0,
      SubmitDraft,
    ).0
  let operation = posting.submission_id

  // A verified refresh may remove the root while GitHub is creating the reply.
  let without_root = pending_verified_refresh(posting, pending_empty_bundle())
  let reply = {
    ..review_comment_fixture(70, reply_to=Some(root.id)),
    path: "response-path.mbt",
    body: "reply body",
  }
  let published = update(
      without_root,
      ReviewReplyCreated(7, operation, Ok(reply)),
    ).0
  let original = published.read_view(path="original.mbt")
  assert_eq(original.pending_review_receipts.length(), 1)
  assert_eq(original.pending_review_receipts[0].path, "original.mbt")
  assert_true(original.pending_review_receipts[0].kind == ReplyDraft(root.id))
  assert_true(original.draft().unwrap().submitting)
  assert_eq(original.draft().unwrap().body, "reply body")
  assert_true(published.read_view(path="response-path.mbt").draft() is None)
  assert_true(
    published.read_view(path="response-path.mbt").pending_review_receipts.is_empty(),
  )
  assert_eq(published.read_view(paths=[]).pending_review_receipts.length(), 1)
  assert_true(
    published.read_view(paths=["original.mbt"]).pending_review_receipts.is_empty(),
  )
}
