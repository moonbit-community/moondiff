///|
fn body_bundle() -> ApiCommentBundle {
  {
    issue_comments: [
      {
        id: 1L,
        body: "Overall",
        html_url: "https://example.test/issue/1",
        created_at: "today",
        user: None,
      },
    ],
    review_comments: [
      { ..review_comment_fixture(1), path: "a.mbt", },
      { ..review_comment_fixture(2, reply_to=Some(1L)), path: "a.mbt", },
      { ..review_comment_fixture(3), path: "b.mbt", },
    ],
    commit_comments: [
      {
        id: 1L,
        body: "Commit",
        html_url: "https://example.test/commit/1",
        created_at: "today",
        user: None,
        path: Some("a.mbt"),
        position: Some(3),
        line: Some(2),
      },
    ],
  }
}

///|
test "anonymous readers expand each comment kind and reply independently" {
  let initial = update(
      session_list(session_fixture(), body_bundle()),
      Identity(false, None),
    ).0
  let ids = [
    IssueComment(1L),
    ReviewComment(1L),
    ReviewComment(2L),
    CommitComment(1L),
  ]
  let mut session = initial
  for id in ids {
    let (next, effects) = update(session, ToggleCommentBody(7, id))
    assert_true(effects.is_empty())
    assert_true(next.expanded_bodies.contains(id))
    session = next
  }
  assert_true(initial.expanded_bodies.is_empty())
  assert_eq(session.expanded_bodies.length(), 4)
  let collapsed = update(session, ToggleCommentBody(7, ReviewComment(1L))).0
  assert_false(
    collapsed.read_view(path="a.mbt").body_expanded(ReviewComment(1L)),
  )
  assert_true(
    collapsed.read_view(path="a.mbt").body_expanded(ReviewComment(2L)),
  )
  assert_true(
    collapsed.read_view(path="a.mbt").body_expanded(CommitComment(1L)),
  )
  assert_true(
    collapsed
    .read_view(paths=["a.mbt", "b.mbt"])
    .body_expanded(IssueComment(1L)),
  )
}

///|
test "comment expansion survives refresh and is pruned when a comment disappears" {
  let bundle = body_bundle()
  let initial = session_list(session_fixture(), bundle)
  let expanded = update(initial, ToggleCommentBody(7, ReviewComment(1L))).0
  let refreshed = session_list(expanded, {
    ..bundle,
    review_comments: bundle.review_comments.map(c => { ..c, body: "Updated", }),
  })
  assert_true(
    refreshed.read_view(path="a.mbt").body_expanded(ReviewComment(1L)),
  )
  let removed = session_list(refreshed, { ..bundle, review_comments: [], })
  assert_true(removed.expanded_bodies.is_empty())
  let restored = session_list(removed, bundle)
  assert_false(
    restored.read_view(path="a.mbt").body_expanded(ReviewComment(1L)),
  )
}

///|
test "successful deletion clears expansion and rejects delayed toggle events" {
  let initial = session_list(session_fixture(), body_bundle())
  let expanded = update(initial, ToggleCommentBody(7, ReviewComment(1L))).0
  let confirming = update(expanded, AskDelete(ReviewComment(1L))).0
  let deleting = update(confirming, ConfirmCommentDelete(ReviewComment(1L))).0
  let deleted = update(
      deleting,
      CommentDeleted(
        7,
        deleting.deletion_id,
        ReviewComment(1L),
        Ok({ deleted: true, }),
      ),
    ).0
  assert_true(deleted.expanded_bodies.is_empty())
  let (ignored, effects) = update(
    deleted,
    ToggleCommentBody(7, ReviewComment(1L)),
  )
  assert_true(@identity.same(ignored, deleted))
  assert_true(effects.is_empty())
}

///|
test "expansion rejects stale generations and absent comments without changing state" {
  let initial = session_list(session_fixture(), body_bundle())
  for
    event in [
      ToggleCommentBody(6, ReviewComment(1L)),
      ToggleCommentBody(8, ReviewComment(1L)),
      ToggleCommentBody(7, ReviewComment(99L)),
    ] {
    let (ignored, effects) = update(initial, event)
    assert_true(@identity.same(ignored, initial))
    assert_true(effects.is_empty())
  }
}

///|
test "expansion is page-local and is omitted from restored navigation" {
  let initial = session_list(session_fixture(), body_bundle())
  let expanded = update(initial, ToggleCommentBody(7, ReviewComment(1L))).0
  let same_context = update(expanded, ContextChanged(expanded.context)).0
  assert_eq(same_context.expanded_bodies.length(), 1)
  let next_page = update(
      expanded,
      ContextChanged({ ..expanded.context, generation: 8, }),
    ).0
  assert_true(next_page.expanded_bodies.is_empty())
  let reset = update(expanded, Reset(true, true)).0
  assert_true(reset.expanded_bodies.is_empty())
  let restored = update(
      reset,
      RestoreNavigation(expanded.export_navigation(), ["a.mbt", "b.mbt"]),
    ).0
  assert_true(restored.expanded_bodies.is_empty())
}

///|
test "expansion projects only the owning file or overall discussion group" {
  let initial = session_list(session_fixture(), body_bundle())
  let paths = ["a.mbt", "b.mbt"]
  let a = initial.read_view(path="a.mbt")
  let b = initial.read_view(path="b.mbt")
  let overall = initial.read_view(paths~)
  let expanded = update(initial, ToggleCommentBody(7, ReviewComment(2L))).0
  assert_false(a == expanded.read_view(path="a.mbt"))
  assert_true(b == expanded.read_view(path="b.mbt"))
  assert_true(overall == expanded.read_view(paths~))
  assert_eq(initial.comment_version(), expanded.comment_version())
  assert_true(
    @identity.same(
      initial.file_comments("a.mbt"),
      expanded.file_comments("a.mbt"),
    ),
  )
  let issue = update(expanded, ToggleCommentBody(7, IssueComment(1L))).0
  assert_true(expanded.read_view(path="a.mbt") == issue.read_view(path="a.mbt"))
  assert_false(expanded.read_view(paths~) == issue.read_view(paths~))
  let orphan = issue.read_view(paths=["b.mbt"])
  assert_true(orphan.body_expanded(ReviewComment(2L)))
  assert_true(orphan.body_expanded(IssueComment(1L)))
}
