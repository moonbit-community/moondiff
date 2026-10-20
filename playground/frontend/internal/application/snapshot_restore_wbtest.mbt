///|
test "fixed commit pages regain write permission after same-account sign-in and restoration" {
  for
    target in [
      ChangeTarget::Commit("a".repeat(40)),
      PullCommit("17", "a".repeat(40)),
    ] {
    for restoring in [false, true] {
      let view = review_test_view(target~)
      let initial = {
        ..navigation_review_model(),
        route: Some(view.reference),
        phase: Showing(view),
      }
      let expired = home_step(initial, Auth(SessionInvalidated))
      assert_false(writes_allowed(expired))
      let checking = if restoring {
        home_step(expired, Auth(RestoreAuth))
      } else {
        expired
      }
      let ready = home_step(
        checking,
        Auth(
          ReactivationAuthStatusLoaded(
            checking.auth_revision,
            checking.generation,
            checking.route,
            Ok(signed_in_api_status("reviewer")),
          ),
        ),
      )
      assert_true(ready.access.freshness is Confirmed)
      assert_true(writes_allowed(ready))
      assert_false(ready.restore_pending)
      assert_eq(ready.generation, initial.generation)
      assert_true(ready.phase == initial.phase)
      let posting = home_step(
        home_step(
          home_step(
            ready,
            Review(
              OpenInlineDraft(0, {
                path: "src/main.mbt",
                side: Right,
                line: 2,
                position: Some(3),
              }),
            ),
          ),
          Review(DraftBodyChanged("New commit comment")),
        ),
        Review(SubmitDraft),
      )
      assert_true(posting.review.submission() is Some(PostingCommit))
    }
  }
}

///|
test "restored PRs keep their shown content and drafts locked until validation succeeds" {
  let editing = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("Keep this draft")),
  )
  let folded = home_step(editing, Load(ToggleFile(editing.generation, 0)))
  guard folded.phase is Showing(view) else { fail("view") }
  let snapshot : @github_client.SnapshotResult = {
    confirmed: true,
    snapshot: {
      metadata: view.pull_snapshot.unwrap(),
      comparison: {
        merge_base_commit: { sha: view.old_revision.unwrap().sha, },
      },
      files: view.files.map(file => file.file),
      signature: "fixture",
    },
  }
  for
    freshness in [
      SnapshotFreshness::Checking,
      Unavailable("Interrupted validation"),
    ] {
    let checking = home_step(
      { ..folded, access: { ..folded.access, freshness, }, },
      Auth(RestoreAuth),
    )
    let restored = home_step(
      checking,
      Auth(
        ReactivationAuthStatusLoaded(
          checking.auth_revision,
          checking.generation,
          checking.route,
          Ok(signed_in_api_status("reviewer")),
        ),
      ),
    )
    assert_false(restored.restore_pending)
    assert_true(restored.access.freshness is Checking)
    assert_false(writes_allowed(restored))
    assert_true(restored.phase == folded.phase)
    assert_true(restored.review.draft() == folded.review.draft())
    let denied = home_step(restored, Review(SubmitDraft))
    assert_true(denied.review.submission() is None)
    let confirmed = home_step(
      denied,
      Load(SharedSnapshotLoaded(denied.generation, Ok(snapshot))),
    )
    assert_true(writes_allowed(confirmed))
    assert_true(confirmed.phase == folded.phase)
    assert_true(confirmed.review.draft() == denied.review.draft())
    assert_true(
      home_step(confirmed, Review(SubmitDraft)).review.submission()
      is Some(PostingIssue),
    )
  }
}

///|
test "restored validation failures remain retryable and old generations cannot overwrite a new route" {
  let initial = navigation_review_model()
  let failure = Load(
    SharedSnapshotLoaded(
      initial.generation,
      Err(GitHubRequestError::GitHubRequestError("Validation unavailable")),
    ),
  )
  let failed = home_step(initial, failure)
  assert_true(failed.access.freshness is Unavailable(_))
  assert_false(writes_allowed(failed))
  assert_true(failed.phase == initial.phase)
  let retrying = home_step(
    failed,
    Auth(
      ReactivationAuthStatusLoaded(
        failed.auth_revision,
        failed.generation,
        failed.route,
        Ok(signed_in_api_status("reviewer")),
      ),
    ),
  )
  assert_true(retrying.access.freshness is Checking)
  let navigated = home_step(
    retrying,
    Ui(RouteChanged(@url.parse("http://localhost/upstream/project/pull/18"))),
  )
  assert_true(navigated.generation > retrying.generation)
  assert_true(home_step(navigated, failure) == navigated)
}

///|
test "restoring a cached large PR preserves its selector and validation generation" {
  let pull = { ..review_test_pull(), changed_files: 3001, commits: Some(251), }
  let comparison : ApiCompare = { merge_base_commit: { sha: "b".repeat(40), }, }
  let shown = show_pull_selector(navigation_review_model(), pull, comparison, _ => {
      @rabbita.none
    }).0
  let commits = pull_page_items(0, 100, 251, pull.head.sha)
  let shown = {
    ..shown,
    range: Some({
      ..shown.range.unwrap(),
      commits,
      from_sha: commits[10].sha,
      to_sha: commits[50].sha,
      loading_page: Some(2),
      next_page: Some(2),
      expanded: true,
    }),
  }
  for
    freshness in [
      SnapshotFreshness::Checking,
      Unavailable("Interrupted validation"),
    ] {
    let checking = home_step(
      { ..shown, access: { ..shown.access, freshness, }, },
      Auth(RestoreAuth),
    )
    let restored = home_step(
      checking,
      Auth(
        ReactivationAuthStatusLoaded(
          checking.auth_revision,
          checking.generation,
          checking.route,
          Ok(signed_in_api_status("reviewer")),
        ),
      ),
    )
    assert_true(restored.access.freshness is Checking)
    let snapshot : @github_client.PullSnapshot = {
      metadata: pull,
      comparison,
      files: [],
      signature: "fixture",
    }
    let cached = home_step(
      restored,
      Load(
        SharedSnapshotLoaded(
          restored.generation,
          Ok({ snapshot, confirmed: false, }),
        ),
      ),
    )
    assert_eq(cached.generation, restored.generation)
    assert_true(cached.phase == restored.phase)
    assert_true(cached.range == restored.range)
    let confirmed = home_step(
      cached,
      Load(
        SharedSnapshotLoaded(
          cached.generation,
          Ok({ snapshot, confirmed: true, }),
        ),
      ),
    )
    assert_true(confirmed.access.freshness is Confirmed)
    assert_eq(confirmed.generation, restored.generation)
    assert_true(confirmed.range == restored.range)
  }
}

///|
fn shown_snapshot(model : Model) -> @github_client.PullSnapshot {
  match model.phase {
    Showing(view) =>
      {
        metadata: view.pull_snapshot.unwrap(),
        comparison: {
          merge_base_commit: { sha: view.old_revision.unwrap().sha, },
        },
        files: view.files.map(file => file.file),
        signature: "fixture",
      }
    ShowingPullSelector(pull) =>
      {
        metadata: pull,
        comparison: {
          merge_base_commit: {
            sha: model.range.unwrap().pull_merge_base.unwrap(),
          },
        },
        files: [],
        signature: "fixture",
      }
    _ => abort("shown snapshot")
  }
}

///|
test "validation retries retain ordinary and large PR contents generation and selection on repeated failure" {
  let edited = home_step(
    home_step(navigation_review_model(), Review(OpenOverallDraft)),
    Review(DraftBodyChanged("Retained through retries")),
  )
  let large = show_pull_selector(
      navigation_review_model(),
      { ..review_test_pull(), changed_files: 3001, commits: Some(251), },
      { merge_base_commit: { sha: "b".repeat(40), }, },
      _ => @rabbita.none,
    ).0
  for initial in [edited, large] {
    let initial = {
      ..initial,
      range: Some({
        ..initial.range.unwrap_or(
          pull_range_state(review_test_pull(), "b".repeat(40)),
        ),
        from_sha: "selected from",
        to_sha: "selected to",
        expanded: true,
      }),
    }
    let mut current = initial
    for _ in 0..<2 {
      let failed = home_step(
        current,
        Load(
          SharedSnapshotLoaded(
            current.generation,
            Err(
              @github_client.HttpRequestError(
                status=503,
                code="unavailable",
                detail="Try later",
              ),
            ),
          ),
        ),
      )
      assert_true(failed.phase == initial.phase)
      assert_true(failed.range == initial.range)
      assert_true(failed.review.draft() == initial.review.draft())
      assert_eq(failed.generation, initial.generation)
      assert_false(writes_allowed(failed))
      assert_true(failed.access.freshness is Unavailable(_))
      let retrying = home_step(failed, Ui(RetryRoute))
      assert_true(retrying.phase == initial.phase)
      assert_true(retrying.range == initial.range)
      assert_true(retrying.review.draft() == initial.review.draft())
      assert_eq(retrying.generation, initial.generation)
      assert_true(retrying.access.freshness is Checking)
      assert_true(home_step(retrying, Ui(RetryRoute)) == retrying)
      current = retrying
    }
    let confirmed = home_step(
      current,
      Load(
        SharedSnapshotLoaded(
          current.generation,
          Ok({ snapshot: shown_snapshot(initial), confirmed: true, }),
        ),
      ),
    )
    assert_true(confirmed.phase == initial.phase)
    assert_true(confirmed.range == initial.range)
    assert_eq(confirmed.generation, initial.generation)
    assert_true(writes_allowed(confirmed))
  }
}

///|
test "display-only metadata refresh preserves original inline anchors file caches and Viewed draft targeting" {
  let edited = home_step(
    home_step(
      navigation_review_model(),
      Review(
        OpenInlineDraft(0, {
          path: "src/main.mbt",
          side: Right,
          line: 2,
          position: Some(3),
        }),
      ),
    ),
    Review(DraftBodyChanged("Original anchor")),
  )
  guard edited.phase is Showing(view) && view.pull_snapshot is Some(pull) else {
    fail("view")
  }
  let original = edited.review.draft().unwrap().snapshot.unwrap()
  for
    metadata in [
      { ..pull, title: "Renamed title", },
      { ..pull, html_url: "https://github.com/upstream/renamed/pull/17", },
      { ..pull, additions: 120, deletions: 60, },
    ] {
    let snapshot = { ..shown_snapshot(edited), metadata, }
    let checking = home_step(
      edited,
      Load(
        SharedSnapshotLoaded(
          edited.generation,
          Ok({ snapshot, confirmed: false, }),
        ),
      ),
    )
    let ready = home_step(
      checking,
      Load(
        SharedSnapshotLoaded(
          checking.generation,
          Ok({ snapshot, confirmed: true, }),
        ),
      ),
    )
    assert_eq(ready.generation, edited.generation)
    assert_false(ready.review.snapshot_stale)
    assert_true(@comments.permission(ready.review, Submit).allowed())
    assert_true(ready.review.draft() == edited.review.draft())
    assert_true(viewed_draft_file(ready) == Some(0))
    let current = comment_context(ready).snapshot.unwrap()
    assert_true(original != current)
    assert_true(original.same_version(current))
    guard ready.phase is Showing(updated) else { fail("updated") }
    assert_eq(updated.message, metadata.title)
    assert_eq(updated.html_url, metadata.html_url)
    assert_true(updated.stats == @github.pull_stats(metadata))
    assert_true(@identity.same(updated.files, view.files))
  }
}

///|
test "semantic versions reject changed repositories SHAs file counts commit counts and references" {
  let edited = home_step(
    home_step(
      navigation_review_model(),
      Review(
        OpenInlineDraft(0, {
          path: "src/main.mbt",
          side: Right,
          line: 2,
          position: Some(3),
        }),
      ),
    ),
    Review(DraftBodyChanged("Old version")),
  )
  guard edited.phase is Showing(view) && view.pull_snapshot is Some(pull) else {
    fail("view")
  }
  let original = comment_context(edited).snapshot.unwrap()
  let versions = [
    { ..original, sha: "changed display SHA", },
    { ..original, reference: @github.pull_reference("other", "repo", "17"), },
    { ..original, pull_snapshot: None, },
  ]
  for
    changed in [
      { ..pull, head: { ..pull.head, sha: "d".repeat(40), }, },
      { ..pull, base: { ..pull.base, sha: "d".repeat(40), }, },
      {
        ..pull,
        head: { ..pull.head, repo: Some({ full_name: "other/repo", }), },
      },
      { ..pull, base: { ..pull.base, repo: None, }, },
      { ..pull, changed_files: pull.changed_files + 1, },
      { ..pull, commits: Some(pull.commits.unwrap_or(0) + 1), },
    ] {
    versions.push({ ..original, pull_snapshot: Some(changed), })
  }
  for current in versions {
    assert_false(original.same_version(current))
    let review = comment_session_context(edited.review, {
      ..comment_context(edited),
      snapshot: Some(current),
    })
    assert_true(review.snapshot_stale)
    assert_false(@comments.permission(review, Submit).allowed())
    assert_true(review.draft() == edited.review.draft())
  }
  let metadata = { ..pull, head: { ..pull.head, sha: "d".repeat(40), }, }
  let replaced = home_step(
    edited,
    Load(
      SharedSnapshotLoaded(
        edited.generation,
        Ok({
          snapshot: { ..shown_snapshot(edited), metadata, },
          confirmed: true,
        }),
      ),
    ),
  )
  assert_true(replaced.generation > edited.generation)
  assert_true(replaced.review.draft().unwrap().snapshot == Some(original))
  assert_false(@comments.permission(replaced.review, Submit).allowed())
  assert_true(viewed_draft_file(replaced) is None)
}
