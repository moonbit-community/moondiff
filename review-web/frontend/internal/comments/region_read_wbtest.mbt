///|
test "comment index preserves unrelated path groups and excludes draft text from permissions" {
  let first = { ..review_comment_fixture(1), path: "a.mbt", }
  let second = { ..review_comment_fixture(2), path: "b.mbt", }
  let bundle : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [first, second],
    commit_comments: [],
  }
  let initial = session_list(session_fixture(), bundle)
  let a = initial.file_comments("a.mbt")
  let b = initial.file_comments("b.mbt")
  let updated = session_list(initial, {
    ..bundle,
    review_comments: [{ ..first, body: "updated", }, second],
  })
  assert_false(@identity.same(a, updated.file_comments("a.mbt")))
  assert_true(@identity.same(b, updated.file_comments("b.mbt")))
  assert_true(updated.comment_version() > initial.comment_version())
  let opened = update(
      updated,
      OpenInlineDraft(0, {
        path: "a.mbt",
        side: Right,
        line: 1,
        position: Some(1),
      }),
    ).0
  let typed = update(opened, DraftBodyChanged("draft text")).0
  assert_eq(typed.comment_version(), opened.comment_version())
  assert_true(typed.permission_summary() == opened.permission_summary())
  assert_true(opened.read_view(path="b.mbt") == typed.read_view(path="b.mbt"))
  assert_false(opened.read_view(path="a.mbt") == typed.read_view(path="a.mbt"))
}

///|
test "reply ownership follows its root, and missing paths belong to overall discussions" {
  let root = { ..review_comment_fixture(1), path: "a.mbt", }
  let reply = {
    ..review_comment_fixture(2),
    path: "wrong.mbt",
    in_reply_to_id: Some(1L),
  }
  let session = session_list(session_fixture(), {
    issue_comments: [],
    review_comments: [root, reply],
    commit_comments: [],
  })
  assert_eq(session.file_comments("a.mbt").review_comments.length(), 2)
  assert_true(session.file_comments("wrong.mbt").review_comments.is_empty())
  assert_eq(session.overall_comments([]).review_comments.length(), 2)
  assert_eq(session.overall_comments(["a.mbt"]).review_comments.length(), 0)
}
