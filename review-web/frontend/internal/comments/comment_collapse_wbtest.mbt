///|
test "manual collapse is independent, typed, anonymous and idempotent" {
  let initial = update(
      session_list(session_fixture(), body_bundle()),
      Identity(false, None),
    ).0
  let root = ReviewComment(1L)
  let expanded = update(initial, SetCommentBodyExpanded(7, root, true)).0
  let (collapsed, effects) = update(
    expanded,
    SetCommentCollapsed(7, root, true),
  )
  assert_true(effects.is_empty())
  assert_true(collapsed.read_view(path="a.mbt").comment_collapsed(root))
  assert_true(collapsed.read_view(path="a.mbt").body_expanded(root))
  assert_false(initial.read_view(path="a.mbt").comment_collapsed(root))
  assert_false(
    collapsed.read_view(path="a.mbt").comment_collapsed(ReviewComment(2L)),
  )
  assert_false(
    collapsed.read_view(path="a.mbt").comment_collapsed(CommitComment(1L)),
  )
  assert_true(
    @identity.same(
      collapsed,
      update(collapsed, SetCommentCollapsed(7, root, true)).0,
    ),
  )
  let reply = update(collapsed, SetCommentCollapsed(7, ReviewComment(2L), true)).0
  let commit = update(reply, SetCommentCollapsed(7, CommitComment(1L), true)).0
  let reopened = update(commit, SetCommentCollapsed(7, root, false)).0
  assert_false(reopened.read_view(path="a.mbt").comment_collapsed(root))
  assert_true(reopened.read_view(path="a.mbt").body_expanded(root))
  assert_true(
    reopened.read_view(path="a.mbt").comment_collapsed(ReviewComment(2L)),
  )
  assert_true(
    reopened.read_view(path="a.mbt").comment_collapsed(CommitComment(1L)),
  )
  for
    event in [
      SetCommentCollapsed(6, root, false),
      SetCommentCollapsed(8, root, false),
      SetCommentCollapsed(7, ReviewComment(99L), true),
      SetCommentCollapsed(7, IssueComment(1L), true),
    ] {
    assert_true(@identity.same(collapsed, update(collapsed, event).0))
  }
  let general = session_list(initial, {
    ..body_bundle(),
    commit_comments: body_bundle().commit_comments.map(c => { ..c, path: None, }),
  })
  assert_true(
    @identity.same(
      general,
      update(general, SetCommentCollapsed(7, CommitComment(1L), true)).0,
    ),
  )
}

///|
test "collapse retains preview and business state, refreshes and prunes disappearances" {
  let bundle = body_bundle()
  let initial = session_list(session_fixture(), bundle)
  let confirming = update(initial, AskDelete(ReviewComment(1L))).0
  let collapsed = update(
      confirming,
      SetCommentCollapsed(7, ReviewComment(1L), true),
    ).0
  assert_true(collapsed.deletion == confirming.deletion)
  assert_true(collapsed.draft() == confirming.draft())
  let refreshed = session_list(collapsed, {
    ..bundle,
    review_comments: bundle.review_comments.map(c => { ..c, body: "updated", }),
  })
  assert_true(
    refreshed.read_view(path="a.mbt").comment_collapsed(ReviewComment(1L)),
  )
  assert_false(
    refreshed.read_view(path="a.mbt").body_expanded(ReviewComment(1L)),
  )
  let removed = session_list(refreshed, { ..bundle, review_comments: [], })
  assert_true(removed.collapsed_comments.is_empty())
  assert_true(session_list(removed, bundle).collapsed_comments.is_empty())
  let deleting = update(collapsed, ConfirmCommentDelete(ReviewComment(1L))).0
  let deleted = update(
      deleting,
      CommentDeleted(
        7,
        deleting.deletion_id,
        ReviewComment(1L),
        Ok({ deleted: true, }),
      ),
    ).0
  assert_true(deleted.collapsed_comments.is_empty())
  assert_true(
    @identity.same(
      deleted,
      update(deleted, SetCommentCollapsed(7, ReviewComment(1L), true)).0,
    ),
  )
}

///|
test "collapse is scoped to its region and resets at page and snapshot boundaries" {
  let initial = session_list(session_fixture(), body_bundle())
  let collapsed = update(
      initial,
      SetCommentCollapsed(7, ReviewComment(2L), true),
    ).0
  assert_false(
    initial.read_view(path="a.mbt") == collapsed.read_view(path="a.mbt"),
  )
  assert_true(
    initial.read_view(path="b.mbt") == collapsed.read_view(path="b.mbt"),
  )
  assert_true(
    initial.read_view(paths=["a.mbt", "b.mbt"]) ==
    collapsed.read_view(paths=["a.mbt", "b.mbt"]),
  )
  assert_true(
    collapsed.read_view(paths=["b.mbt"]).comment_collapsed(ReviewComment(2L)),
  )
  assert_eq(initial.comment_version(), collapsed.comment_version())
  assert_true(
    @identity.same(
      initial.file_comments("a.mbt"),
      collapsed.file_comments("a.mbt"),
    ),
  )
  assert_eq(
    update(collapsed, ContextChanged(collapsed.context)).0.collapsed_comments.length(),
    1,
  )
  let snapshot = collapsed.context.snapshot.unwrap()
  for
    context in [
      { ..collapsed.context, generation: 8, },
      {
        ..collapsed.context,
        route: Some({ ..snapshot.reference, target: Commit("other"), }),
      },
      { ..collapsed.context, snapshot: Some({ ..snapshot, sha: "new", }), },
    ] {
    assert_true(
      update(collapsed, ContextChanged(context)).0.collapsed_comments.is_empty(),
    )
  }
  let reset = update(collapsed, Reset(true, true)).0
  assert_true(reset.collapsed_comments.is_empty())
  assert_true(
    update(reset, RestoreNavigation(collapsed.export_navigation(), ["a.mbt"])).0.collapsed_comments.is_empty(),
  )
}
