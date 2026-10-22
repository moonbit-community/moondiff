///|
fn restore_viewed_auth(model : Model) -> Model {
  viewed_interaction_update(
    model,
    Auth(
      ReactivationAuthStatusLoaded(
        model.auth_revision,
        model.generation,
        model.route,
        Ok({ ..signed_in_api_status("alice"), user_id: Some("1"), }),
      ),
    ),
  )
}

///|
test "Viewed restoration retains interrupted writes through repeated checks and read failures" {
  for before in [@protocol.FileViewedState::Viewed, Unviewed, Dismissed] {
    let loaded = viewed_test_loaded(viewed_test_model(), before)
    let writing = viewed_test_toggle(loaded)
    let original = writing.viewed.files[0].pending.unwrap()
    let mut checking = viewed_interaction_update(writing, Auth(RestoreAuth))
    for _ in 0..<2 {
      assert_true(checking.viewed.user_id == Some("1"))
      assert_true(
        checking.viewed.files[0].pending ==
        Some({ ..original, confirming: true, }),
      )
      assert_true(
        checking.viewed.files[0].state == writing.viewed.files[0].state,
      )
      assert_false(checking.viewed.ready)
      checking = viewed_interaction_update(checking, Auth(RestoreAuth))
    }
    let restored = restore_viewed_auth(checking)
    assert_true(restored.viewed.loading)
    assert_false(restored.viewed.ready)
    assert_true(viewed_test_toggle(restored) == restored)
    let failed = viewed_interaction_update(
      restored,
      Viewed(
        Loaded(
          restored.viewed.epoch,
          restored.viewed.serial,
          Err(
            @github_client.HttpRequestError(
              status=503,
              code="unavailable",
              detail="retry",
            ),
          ),
        ),
      ),
    )
    assert_false(failed.viewed.ready)
    assert_true(
      failed.viewed.files[0].pending == restored.viewed.files[0].pending,
    )
    // Even a successful old response cannot settle the retained write.
    let data = viewed_test_data(
      if before is Viewed {
        Unviewed
      } else {
        Viewed
      },
    )
    let late = viewed_interaction_update(
      failed,
      Viewed(
        Saved(
          writing.viewed.epoch,
          0,
          original.record.id,
          Ok({
            base_sha: data.base_sha,
            head_sha: data.head_sha,
            file: data.files[0],
          }),
        ),
      ),
    )
    assert_true(late == failed)
    let retry = viewed_interaction_update(failed, Viewed(Refresh))
    let confirmed = viewed_test_loaded(retry, data.files[0].state)
    assert_true(confirmed.viewed.ready)
    assert_true(confirmed.viewed.files[0].pending is None)
    assert_true(
      viewed_test_expanded(confirmed) == viewed_test_expanded(writing),
    )
    let not_applied = viewed_test_loaded(retry, before)
    assert_true(
      not_applied.viewed.files[0].state == writing.viewed.files[0].state,
    )
    assert_true(not_applied.viewed.files[0].pending is Some(_))
    assert_eq(viewed_test_expanded(not_applied), viewed_test_expanded(writing))
  }
}

///|
test "Viewed interrupted confirmation preserves later expansion and draft interactions" {
  let loaded = viewed_test_loaded(viewed_test_model(), Viewed)
  let writing = viewed_test_toggle(loaded)
  for
    msg in [
      Load(OpenFile(writing.generation, 0)),
      Review(OpenInlineDraft(0, viewed_interaction_anchor())),
    ] {
    let touched = viewed_interaction_update(writing, msg)
    let checking = viewed_interaction_update(touched, Auth(RestoreAuth))
    let restored = restore_viewed_auth(checking)
    let not_applied = viewed_test_loaded(restored, Viewed)
    assert_true(viewed_test_expanded(not_applied))
    assert_true(not_applied.review.draft() == touched.review.draft())
    assert_true(not_applied.viewed.files[0].pending is Some(_))
  }
}

///|
test "Viewed interrupted state never crosses an account page or snapshot boundary" {
  let writing = viewed_test_toggle(
    viewed_test_loaded(viewed_test_model(), Unviewed),
  )
  let checking = viewed_interaction_update(writing, Auth(RestoreAuth))
  guard checking.phase is Showing(view) && view.pull_snapshot is Some(snapshot) else {
    fail("missing view")
  }
  for
    next in [
      with_auth(
        checking,
        SignedIn(user_id=Some("2"), login=Some("alice"), install_url=None),
      ),
      with_auth(checking, Anonymous(None)),
      { ..checking, generation: checking.generation + 1, },
      with_phase(
        checking,
        Showing({
          ..view,
          pull_snapshot: Some({
            ..snapshot,
            head: { ..snapshot.head, sha: "changed", },
          }),
        }),
      ),
    ] {
    let reset = reconcile_viewed(checking, next, Viewed(Refresh), _ => {
        @rabbita.none
      }).0
    assert_true(
      reset.viewed.files.all(file => file.pending is None && file.state is None),
    )
    assert_false(reset.viewed.ready)
    assert_true(reset.viewed.epoch > checking.viewed.epoch)
  }
  let restored = restore_viewed_auth(checking)
  let data = { ..viewed_test_data(Unviewed), head_sha: "b".repeat(40), }
  let stale = viewed_interaction_update(
    restored,
    Viewed(Loaded(restored.viewed.epoch, restored.viewed.serial, Ok(data))),
  )
  assert_true(stale.viewed.stale && stale.review.snapshot_stale)
  assert_true(viewed_test_toggle(stale) == stale)
}
