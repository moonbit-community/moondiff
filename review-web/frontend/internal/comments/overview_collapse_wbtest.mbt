///|
test "overview collapse is anonymous, generation guarded and idempotent in every status" {
  let initial = update(session_fixture(), Identity(false, None)).0
  let loading = update(initial, RefreshComments).0
  let failed = update(
      loading,
      CommentsLoaded(
        7,
        loading.refresh_id,
        Err({ message: "offline", code: None, }),
      ),
    ).0
  for
    session in [initial, loading, failed, session_list(initial, body_bundle())] {
    assert_false(session.read_view().overview_collapsed)
    let (collapsed, effects) = update(session, SetOverviewCollapsed(7, true))
    assert_true(effects.is_empty())
    assert_true(collapsed.read_view().overview_collapsed)
    assert_false(session.read_view().overview_collapsed)
    assert_true(
      session.read_view(path="a.mbt") == collapsed.read_view(path="a.mbt"),
    )
    assert_eq(session.comment_version(), collapsed.comment_version())
    for
      event in [
        SetOverviewCollapsed(7, true),
        SetOverviewCollapsed(6, false),
        SetOverviewCollapsed(8, false),
      ] {
      let (unchanged, effects) = update(collapsed, event)
      assert_true(@identity.same(collapsed, unchanged))
      assert_true(effects.is_empty())
    }
    assert_true(update(collapsed, SetOverviewCollapsed(7, false)).0 == session)
  }
}

///|
test "overview collapse preserves reading and editor state and stays out of navigation" {
  let initial = session_list(session_fixture(), body_bundle())
  let expanded = update(
      initial,
      SetCommentBodyExpanded(7, ReviewComment(1L), true),
    ).0
  let folded = update(expanded, SetCommentCollapsed(7, ReviewComment(2L), true)).0
  let editing = update(
      folded,
      OpenInlineDraft(0, {
        path: "a.mbt",
        side: Right,
        line: 1,
        position: Some(1),
      }),
    ).0
  let editing = update(editing, DraftBodyChanged("Keep this draft")).0
  assert_eq(editing.draft().unwrap().body, "Keep this draft")
  let collapsed = update(editing, SetOverviewCollapsed(7, true)).0
  assert_true(editing.export_navigation() == collapsed.export_navigation())
  assert_true(collapsed.draft() == editing.draft())
  let refreshed = session_list(collapsed, body_bundle())
  assert_true(refreshed.read_view().overview_collapsed)
  assert_true(
    refreshed.read_view(path="a.mbt").body_expanded(ReviewComment(1L)),
  )
  assert_true(
    refreshed.read_view(path="a.mbt").comment_collapsed(ReviewComment(2L)),
  )
  assert_true(refreshed.draft() == editing.draft())
  assert_true(
    update(collapsed, ContextChanged(collapsed.context)).0.read_view().overview_collapsed,
  )
  let snapshot = collapsed.context.snapshot.unwrap()
  assert_true(
    update(
      collapsed,
      ContextChanged({
        ..collapsed.context,
        snapshot: Some({ ..snapshot, sha: "new", }),
      }),
    ).0.read_view().overview_collapsed,
  )
  for
    context in [
      { ..collapsed.context, generation: 8, },
      {
        ..collapsed.context,
        route: Some({ ..snapshot.reference, target: Commit("other"), }),
      },
    ] {
    assert_false(
      update(collapsed, ContextChanged(context)).0.read_view().overview_collapsed,
    )
  }
  let reset = update(collapsed, Reset(true, true)).0
  assert_false(reset.read_view().overview_collapsed)
  assert_false(
    update(reset, RestoreNavigation(collapsed.export_navigation(), ["a.mbt"])).0.read_view().overview_collapsed,
  )
}
