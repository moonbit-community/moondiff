///|
fn navigation_review_model() -> Model {
  review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
}

///|
test "submission keeps only the last navigation intent and failures clear it" {
  let edited = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("body")),
  )
  let posting = home_step(edited, Review(SubmitDraft))
  assert_true(navigation_blocked(posting))
  let first = home_step(posting, Ui(Navigate("/upstream/repo/pull/2")))
  let last = home_step(first, Ui(Navigate("/")))
  assert_true(last.navigation.pending is Some(Path("/")))
  assert_eq(last.generation, posting.generation)
  let failed = home_step(
    last,
    Review(
      IssueCommentCreated(
        last.generation,
        last.review.submission_id,
        Err(GitHubRequestError::GitHubRequestError("write failed")),
      ),
    ),
  )
  assert_true(failed.navigation.pending is None)
  assert_true(failed.route == posting.route)
  assert_true(
    failed.review.draft() is Some({ body: "body", error: Some(_), .. }),
  )
}

///|
test "draft restore preserves the original anchor when a route has a newer version" {
  let initial = navigation_review_model()
  let anchor = ReviewAnchor::{
    path: "src/main.mbt",
    side: Right,
    line: 2,
    position: Some(3),
  }
  let edited = home_step(
    home_step(initial, Review(OpenInlineDraft(0, anchor))),
    Review(DraftBodyChanged("Old anchor text")),
  )
  let saved = save_route_memory(edited)
  guard saved.phase is Showing(view) && view.pull_snapshot is Some(pull) else {
    fail("view")
  }
  let current = {
    ..view,
    sha: "d".repeat(40),
    pull_snapshot: Some({ ..pull, head: { ..pull.head, sha: "d".repeat(40), }, }),
  }
  let review = comment_session_context(initial_review_state(), {
    generation: 12,
    route: saved.route,
    snapshot: None,
    enabled: true,
  })
  let (next, _) = restore_route_memory(
    with_phase(
      {
        ..saved,
        generation: 12,
        review,
        navigation: { ..saved.navigation, restore_data: true, },
      },
      Showing(current),
    ),
  )
  guard next.review.draft() is Some(draft) else { fail("draft") }
  assert_eq(draft.id.generation, 12)
  assert_eq(draft.body, "Old anchor text")
  assert_true(draft.kind is InlineDraft(_, original) && original == anchor)
  assert_true(draft.snapshot != comment_context(next).snapshot)
  assert_false(@comments.permission(next.review, Submit).allowed())
}

///|
test "snapshot freshness and identity checks gate comments, deletion, Viewed and merge centrally" {
  let model = navigation_review_model()
  let editing = home_step(
    home_step(model, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("wait")),
  )
  let unverified = {
    ..editing,
    access: {
      freshness: Checking,
      identity_checking: false,
      preparing: None,
      reload_requested: false,
    },
  }
  let denied = home_step(unverified, Review(SubmitDraft))
  assert_true(denied.review.submission() is None)
  assert_false(@comments.permission(denied.review, Submit).allowed())
  assert_false(
    @comments.permission(denied.review, Delete(IssueComment(1L))).allowed(),
  )
  assert_false(writes_allowed(denied))
  let identity = {
    ..editing,
    access: {
      freshness: Confirmed,
      identity_checking: true,
      preparing: None,
      reload_requested: false,
    },
  }
  assert_false(writes_allowed(identity))
  let confirmed = home_step(
    { ..editing, access: SnapshotAccess::new(), },
    Review(SubmitDraft),
  )
  assert_true(confirmed.review.submission() is Some(PostingIssue))
}

///|
test "homepage candidates are the first five distinct PRs of the selected tab" {
  let home = home_model()
  let authored = {
    ..home.home.authored,
    items: [
      home_pull("4"),
      home_pull("2"),
      home_pull("4"),
      home_pull("7"),
      home_pull("1"),
      home_pull("8"),
      home_pull("6"),
    ],
  }
  let reviews = { ..home.home.reviews, items: [home_pull("9")], }
  let model = { ..home, home: { ..home.home, authored, reviews, }, }
  assert_eq(
    home_prefetch_candidates(model).map(candidate => candidate.pull.number),
    ["4", "2", "7", "1", "8"],
  )
  let switched = { ..model, home: { ..model.home, tab: ReviewRequested, }, }
  assert_eq(
    home_prefetch_candidates(switched).map(candidate => candidate.pull.number),
    ["9"],
  )
}

///|
test "loading routes cannot overwrite a saved draft and preferences retain multiple versions" {
  let initial = navigation_review_model()
  let editing = home_step(
    home_step(initial, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("Retain during loading")),
  )
  let saved = save_route_memory(editing)
  guard saved.route is Some(reference) &&
    saved.phase is Showing(view) &&
    view.pull_snapshot is Some(pull) else {
    fail("view")
  }
  let loading = {
    ..saved,
    phase: LoadingPullMetadata(reference~, attempt=0),
    review: initial_review_state(),
  }
  assert_true(
    save_route_memory(loading).navigation.routes == saved.navigation.routes,
  )
  let folded = home_step(saved, Load(ToggleFile(saved.generation, 0)))
  let v1 = save_route_memory(folded)
  let v2_view = {
    ..view,
    sha: "d".repeat(40),
    pull_snapshot: Some({ ..pull, head: { ..pull.head, sha: "d".repeat(40), }, }),
  }
  let v2 = save_route_memory(with_phase(v1, Showing(v2_view)))
  let (restored, _) = restore_route_preferences(with_phase(v2, Showing(view)))
  assert_true(restored.phase is Showing({ files, .. }) && !files[0].expanded)
}

///|
test "navigation uses the completed write outcome independently of older draft errors" {
  let editing = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("old draft")),
  )
  let posting = home_step(editing, Review(SubmitDraft))
  let failed = home_step(
    posting,
    Review(
      IssueCommentCreated(
        posting.generation,
        posting.review.submission_id,
        Err(GitHubRequestError::GitHubRequestError("old failure")),
      ),
    ),
  )
  let merging = {
    ..failed,
    pull_merge: { ..failed.pull_merge, submitting: true, },
  }
  let success = {
    ..merging,
    pull_merge: { ..merging.pull_merge, submitting: false, error: None, },
  }
  assert_false(navigation_write_failed(merging, success))
  assert_true(
    navigation_write_failed(merging, {
      ..success,
      pull_merge: { ..success.pull_merge, error: Some("new merge failure"), },
    }),
  )
}

///|
test "a persisted Viewed toggle waits for identity confirmation before sending" {
  let model = viewed_test_loaded(viewed_test_model(), Unviewed)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let pending = update_viewed(model, Toggle(model.generation, 0), emit).0
  guard pending.viewed.files[0].pending is Some(operation) else {
    fail("pending")
  }
  let checking = {
    ..pending,
    access: { ..pending.access, identity_checking: true, },
  }
  let deferred = update_viewed(
      checking,
      Stored(checking.viewed.epoch, 0, operation.record, true),
      emit,
    ).0
  assert_true(
    deferred.viewed.files[0].pending
    is Some({ deferred: true, stored: false, .. }),
  )
  let confirmed = { ..deferred, access: SnapshotAccess::new(), }
  let sent = update_viewed(
      confirmed,
      Stored(confirmed.viewed.epoch, 0, operation.record, true),
      emit,
    ).0
  assert_true(
    sent.viewed.files[0].pending
    is Some({ deferred: false, stored: true, record, .. }) &&
    record.id == operation.record.id,
  )
}

///|
test "restored layout precedes delayed Viewed sync including anonymous restoration and first sign-in" {
  for anonymous in [false, true] {
    let initial = if anonymous {
      review_test_model(Anonymous(None))
    } else {
      viewed_test_loaded(viewed_test_model(), Viewed)
    }
    let opened = home_step(initial, Load(OpenFile(initial.generation, 0)))
    let snapshot = shown_snapshot(opened)
    let home = home_step(
      save_route_memory(opened),
      Ui(RouteChanged(@url.parse("http://localhost/"))),
    )
    let loading = home_step(
      home,
      Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/17"))),
    )
    let restored = home_step(
      loading,
      Load(
        SharedSnapshotLoaded(
          loading.generation,
          Ok({ snapshot, confirmed: true, }),
        ),
      ),
    )
    assert_true(viewed_test_expanded(restored))
    assert_true(restored.viewed.files[0].touched)
    assert_true(restored.viewed.files[0].expansion_revision > 0)
    assert_true(restored.viewed.files[0].state is None)
    assert_true(restored.viewed.files[0].pending is None)
    let signed_in = if anonymous {
      home_step(
        restored,
        Auth(
          ReactivationAuthStatusLoaded(
            restored.auth_revision,
            restored.generation,
            restored.route,
            Ok({ ..signed_in_api_status("alice"), user_id: Some("1"), }),
          ),
        ),
      )
    } else {
      restored
    }
    let ready = viewed_test_loaded(signed_in, Viewed)
    assert_true(viewed_test_expanded(ready))
    assert_true(ready.viewed.files[0].state == Some(Viewed))
    assert_true(ready.viewed.files[0].touched)
    assert_eq(ready.generation, restored.generation)
  }
}

///|
test "layout interactions are scoped to exact versions paths and accounts" {
  let initial = viewed_test_loaded(viewed_test_model(), Viewed)
  let opened = home_step(initial, Load(OpenFile(initial.generation, 0)))
  let snapshot = shown_snapshot(opened)
  let home = home_step(
    save_route_memory(opened),
    Ui(RouteChanged(@url.parse("http://localhost/"))),
  )
  let loading = home_step(
    home,
    Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/17"))),
  )
  for different_path in [false, true] {
    let changed = if different_path {
      {
        ..snapshot,
        files: snapshot.files.map(file => { ..file, filename: "different.mbt", }),
        metadata: {
          ..snapshot.metadata,
          head: { ..snapshot.metadata.head, sha: "d".repeat(40), },
        },
      }
    } else {
      {
        ..snapshot,
        metadata: {
          ..snapshot.metadata,
          head: { ..snapshot.metadata.head, sha: "d".repeat(40), },
        },
      }
    }
    let restored = home_step(
      loading,
      Load(
        SharedSnapshotLoaded(
          loading.generation,
          Ok({ snapshot: changed, confirmed: true, }),
        ),
      ),
    )
    let restored = finish_preparing_fixture(restored)
    assert_false(restored.viewed.files[0].touched)
    assert_eq(restored.viewed.files[0].expansion_revision, 0)
  }
  let restored = home_step(
    loading,
    Load(
      SharedSnapshotLoaded(
        loading.generation,
        Ok({ snapshot, confirmed: true, }),
      ),
    ),
  )
  let switched = home_step(
    restored,
    Auth(
      ReactivationAuthStatusLoaded(
        restored.auth_revision,
        restored.generation,
        restored.route,
        Ok({ ..signed_in_api_status("bob"), user_id: Some("2"), }),
      ),
    ),
  )
  assert_true(switched.navigation.routes.is_empty())
  let shown = home_step(
    switched,
    Load(
      SharedSnapshotLoaded(
        switched.generation,
        Ok({ snapshot, confirmed: true, }),
      ),
    ),
  )
  assert_false(shown.viewed.files[0].touched)
  assert_false(viewed_test_expanded(viewed_test_loaded(shown, Viewed)))
}

///|
test "visibility is model state on both homepage and PR and resumption schedules only eligible homepages" {
  let home = home_model()
  assert_true(prefetch_eligible(home))
  let hidden = home_step(home, Home(VisibilityChanged(false)))
  assert_false(hidden.page_visible)
  assert_false(prefetch_eligible(hidden))
  assert_true(prefetch_after_commit(home, hidden) is None)
  let visible = home_step(hidden, Home(VisibilityChanged(true)))
  assert_true(visible.page_visible)
  assert_true(prefetch_after_commit(hidden, visible) is Some(_))
  assert_true(prefetch_after_commit(visible, visible) is None)
  let pr = navigation_review_model()
  let hidden_pr = home_step(pr, Home(VisibilityChanged(false)))
  assert_false(hidden_pr.page_visible)
  assert_true(hidden_pr.phase == pr.phase)
  assert_false(prefetch_eligible(hidden_pr))
}
