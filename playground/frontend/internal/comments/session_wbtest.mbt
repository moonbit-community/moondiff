///|
fn session_fixture() -> Session {
  let view = review_test_view(target=Commit("head"))
  let (session, _) = update(
    Session::new(enabled=true),
    ContextChanged({
      generation: 7,
      route: Some(view.reference),
      snapshot: Some({
        reference: view.reference,
        sha: view.sha,
        pull_snapshot: None,
      }),
      enabled: true,
    }),
  )
  update(session, Identity(true, Some("reviewer"))).0
}

///|
fn session_list(session : Session, bundle : ApiCommentBundle) -> Session {
  let pending = update(session, RefreshComments).0
  update(pending, CommentsLoaded(7, pending.refresh_id, Ok(bundle))).0
}

///|
test "session views and validation inputs do not expose mutable cache state" {
  let bundle : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [review_comment_fixture(1)],
    commit_comments: [],
  }
  let session = session_list(session_fixture(), bundle)
  bundle.review_comments.clear()
  guard session.comments() is CommentsReady(view) else { fail("ready") }
  view.review_comments.clear()
  guard session.comments() is CommentsReady(still) else { fail("ready") }
  assert_eq(still.review_comments.length(), 1)
  let before = session
  let (next, _) = update(session, AskDelete(ReviewComment(1L)))
  assert_true(before.deletion is None)
  assert_true(next.deletion is Some(ConfirmDelete(_)))
}

///|
test "delete retries reject previous attempts and duplicate receipts without effects" {
  let bundle : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [review_comment_fixture(1)],
    commit_comments: [],
  }
  let initial = session_list(session_fixture(), bundle)
  let confirming = update(initial, AskDelete(ReviewComment(1L))).0
  let first = update(confirming, ConfirmCommentDelete(ReviewComment(1L))).0
  let failed = update(
      first,
      CommentDeleted(
        7,
        first.deletion_id,
        ReviewComment(1L),
        Err({ message: "offline", code: None, }),
      ),
    ).0
  let retrying = update(failed, ConfirmCommentDelete(ReviewComment(1L))).0
  for generation in [6, 7] {
    let (ignored, effects) = update(
      retrying,
      CommentDeleted(
        generation,
        first.deletion_id,
        ReviewComment(1L),
        Ok({ deleted: true, }),
      ),
    )
    assert_true(ignored == retrying)
    assert_true(effects.is_empty())
  }
  let event = Event::CommentDeleted(
    7,
    retrying.deletion_id,
    ReviewComment(1L),
    Ok({ deleted: true, }),
  )
  let deleted = update(retrying, event).0
  let (duplicate, effects) = update(deleted, event)
  assert_true(duplicate == deleted)
  assert_true(effects.is_empty())
  let refreshed = session_list(deleted, bundle)
  guard refreshed.comments() is CommentsReady(after) else { fail("ready") }
  assert_true(after.review_comments.is_empty())
  guard initial.comments() is CommentsReady(before) else { fail("ready") }
  assert_eq(before.review_comments.length(), 1)
}

///|
test "write receipts invalidate old refresh and merge without duplicate comments" {
  let initial = session_fixture()
  let anchor = ReviewAnchor::{
    path: "src/main.mbt",
    line: 2,
    side: Right,
    position: Some(3),
  }
  let draft = update(initial, OpenInlineDraft(0, anchor)).0
  let same = update(draft, OpenInlineDraft(99, anchor)).0
  assert_true(draft.draft().unwrap().id == same.draft().unwrap().id)
  let editing = update(draft, DraftBodyChanged(" frozen body ")).0
  let pending = update(editing, SubmitDraft).0
  let refresh = update(pending, RefreshComments).0
  let created = ApiCommitComment::{
    id: 9L,
    body: "frozen body",
    html_url: "https://example.test/9",
    created_at: "today",
    user: Some({ login: "reviewer", }),
    path: Some(anchor.path),
    position: anchor.position,
    line: Some(anchor.line),
  }
  let event = Event::CommitCommentCreated(7, pending.submission_id, Ok(created))
  let published = update(refresh, event).0
  let empty : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [],
    commit_comments: [],
  }
  let (late, effects) = update(
    published,
    CommentsLoaded(7, refresh.refresh_id, Ok(empty)),
  )
  assert_true(late == published)
  assert_true(effects.is_empty())
  let (duplicate, effects) = update(published, event)
  assert_true(duplicate == published)
  assert_true(effects.is_empty())
  let fresh = session_list(published, empty)
  guard fresh.comments() is CommentsReady(bundle) else { fail("ready") }
  assert_true(bundle.commit_comments == [created])
  let observed = session_list(fresh, bundle)
  guard observed.comments() is CommentsReady(bundle) else { fail("ready") }
  assert_true(bundle.commit_comments == [created])
  assert_eq(editing.draft().unwrap().body, " frozen body ")
}

///|
test "orphaned replies keep the original thread identity" {
  let root = review_comment_fixture(1)
  let first = review_comment_fixture(2, reply_to=Some(1L))
  let second = review_comment_fixture(3, reply_to=Some(1L))
  let view = review_test_view()
  let complete = review_threads(view, [root, first, second])
  let orphaned = review_threads(view, [second, first])
  assert_true(complete[0].id == orphaned[0].id)
  assert_true(orphaned[0].id == ReviewComment(1L))
  let session = session_list(session_fixture(), {
    issue_comments: [],
    review_comments: [first, second],
    commit_comments: [],
  })
  assert_false(valid_reply_target(session, 2L))
}
