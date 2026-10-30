///|
fn region_model() -> Model {
  let files = ["a.mbt", "b.mbt"].map(path => {
    let api = {
      ..fixture_file(path, "modified"),
      patch: Some("@@ -1 +1 @@\n-fn value() { 1 }\n+fn value() { 2 }"),
    }
    ensure_file_document(
      ready_test_file(api, ["fn value() { 1 }"], ["fn value() { 2 }"]),
      LexicalAlgorithm,
    )
  })
  let reference = @github.commit_reference("owner", "repo", "head")
  let view = {
    ..@change.finish_change(
      reference,
      None,
      { repository: { owner: "owner", repo: "repo", }, sha: "head", },
      "Title",
      "",
      { additions: 2, deletions: 2, total: 4, },
      files.map(f => f.file),
    ),
    files,
  }
  let session = @comments.update(
      @comments.Session::new(),
      ContextChanged({
        generation: 1,
        route: Some(reference),
        snapshot: Some({ reference, sha: "head", pull_snapshot: None, }),
        enabled: true,
      }),
    ).0
  let review = @comments.update(session, Identity(true, Some("me"))).0
  {
    input: "",
    navigation: @application.NavigationState::new(),
    access: @application.SnapshotAccess::new(),
    page_visible: true,
    pull_sources: None,
    source_pause: None,
    generation: 1,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(reference),
    file_tree: test_file_tree_state(),
    auth: Anonymous(None),
    auth_revision: 0,
    reading_recovery: None,
    reading_recovery_serial: 0,
    reading_recovery_blocked: false,
    sign_in_dialog: @application.SignInDialog::new(),
    restore_pending: false,
    recovering_session: false,
    last_authenticated_user_id: None,
    home: test_home_state(),
    viewed: test_viewed_state(),
    pull_merge: test_pull_merge_state(),
    review,
    range: None,
  }
}

///|
fn test_file_input(model : Model, index : Int32) -> FileInput {
  guard model.phase is Showing(view) else { panic() }
  file_input(false, model, index, view.files[index])
}

///|
fn pull_region_model() -> Model {
  let model = region_model()
  guard model.phase is Showing(view) else { panic() }
  let reference = @github.pull_reference("owner", "repo", "17")
  let base = "1111111111111111111111111111111111111111"
  let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let pull : @protocol.ApiPull = {
    title: "Pull request",
    body: None,
    user: None,
    html_url: "https://github.com/owner/repo/pull/17",
    base: { sha: base, repo: Some({ full_name: "owner/repo", }), },
    head: { sha: head, repo: Some({ full_name: "owner/repo", }), },
    additions: 2,
    deletions: 2,
    changed_files: 2,
    commits: None,
  }
  {
    ..model,
    route: Some(reference),
    phase: Showing({ ..view, reference, pull_snapshot: Some(pull), sha: head, }),
  }
}

///|
test "every non-home phase projects exactly one fixed Status region including validation failures" {
  let model = pull_region_model()
  let reference = model.route.unwrap()
  let pull = match model.phase {
    Showing(view) => view.pull_snapshot.unwrap()
    _ => abort("pull")
  }
  let phases : Array[@application.Phase] = [
    Idle,
    LoadingPullMetadata(reference~, attempt=0),
    LoadFailed("Failed to load"),
    ShowingPullSelector(pull),
    model.phase,
  ]
  for phase in phases {
    for
      freshness in [
        @application.SnapshotFreshness::Confirmed,
        Checking,
        Unavailable("Validation unavailable"),
      ] {
      let next = { ..model, phase, access: { ..model.access, freshness, }, }
      let inputs = RegionProjection::new().inputs(next)
      assert_eq(inputs.filter(pair => pair.0 is Status).length(), 1)
      assert_true(inputs[0].0 is Toolbar)
      assert_true(inputs[1].0 is Status)
      if phase is LoadFailed(_) {
        assert_true(inputs[1].1 is Status(Failed("Failed to load", _)))
      }
      if (phase is Showing(_) || phase is ShowingPullSelector(_)) &&
        freshness is Confirmed {
        assert_true(inputs[1].1 is Status(Empty))
      }
    }
  }
}

///|
test "shown discussions own authentication errors while large selectors retain their status action" {
  let model = {
    ..pull_region_model(),
    auth: AuthFailed("Session expired"),
    access: {
      freshness: Unavailable("Session expired"),
      preparing: None,
      reload_requested: false,
      waiting_for_viewed: false,
      identity_checking: false,
    },
  }
  let inputs = RegionProjection::new().inputs(model)
  assert_true(inputs[1].1 is Status(Empty))
  guard model.phase is Showing({ pull_snapshot: Some(pull), .. }) else {
    fail("pull")
  }
  let selector = { ..model, phase: ShowingPullSelector(pull), }
  let selector_inputs = RegionProjection::new().inputs(selector)
  assert_true(
    selector_inputs[1].1 is Status(Failed("Session expired", AuthFailed(_))),
  )
}

///|
test "session check selects workspace for every valid share route" {
  let base = "a".repeat(40)
  let head = "b".repeat(40)
  for
    path in [
      "/owner/repo/pull/17",
      "/owner/repo/commit/\{head}",
      "/owner/repo/pull/17/commits/\{head}",
      "/owner/repo/compare/\{base}..\{head}",
      "/owner/repo/pull/17/compare/\{base}..\{head}",
    ] {
    guard @routing.reference_from_route(Some(path)) is Ok(Some(reference)) else {
      fail("expected a valid share route: \{path}")
    }
    let input = @routing.canonical_github_url(reference)
    let model = {
      ..region_model(),
      input,
      generation: 0,
      phase: Idle,
      route: Some(reference),
      auth: AuthChecking,
    }
    let shell = shell_input(model)
    assert_false(shell.home)
    assert_false(shell.landing)
    let regions = RegionProjection::new().inputs(model)
    assert_eq(regions.length(), 2)
    guard regions[0].1 is Toolbar(toolbar) else {
      fail("expected a workspace toolbar")
    }
    assert_false(toolbar.landing)
    assert_eq(toolbar.input, input)
    assert_true(regions[1].1 is Status(Loading("Checking GitHub session…")))
  }
}

///|
test "root session check and invalid routes keep their existing layouts" {
  let root = {
    ..region_model(),
    input: "",
    navigation: @application.NavigationState::new(),
    access: @application.SnapshotAccess::new(),
    page_visible: true,
    pull_sources: None,
    source_pause: None,
    generation: 0,
    phase: Idle,
    route: None,
    auth: AuthChecking,
  }
  let root_shell = shell_input(root)
  assert_true(root_shell.home)
  assert_true(root_shell.landing)
  let root_regions = RegionProjection::new().inputs(root)
  assert_eq(root_regions.length(), 1)
  assert_true(root_regions[0].1 is Home(AuthChecking, _))

  let message = "This shared review link is not valid."
  let invalid = { ..root, phase: LoadFailed(message), }
  let invalid_shell = shell_input(invalid)
  assert_false(invalid_shell.home)
  assert_true(invalid_shell.landing)
  let invalid_regions = RegionProjection::new().inputs(invalid)
  assert_eq(invalid_regions.length(), 2)
  guard invalid_regions[0].1 is Toolbar(toolbar) else {
    fail("expected the link input")
  }
  assert_true(toolbar.landing)
  guard invalid_regions[1].1 is Status(Failed(actual, AuthChecking)) else {
    fail("expected the invalid-link error")
  }
  assert_eq(actual, message)
}

///|
test "file inputs ignore another file, tree controls and draft text outside their owner" {
  let initial = region_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let other = test_file_input(initial, 1)
  for
    msg in [
      @application.Load(ToggleFile(1, 0)),
      Ui(FileTreeSearchChanged("query")),
      Ui(FileTreeWidthChanged(400)),
      Ui(ToggleFileTreeDirectory("src")),
    ] {
    let next = @application.update(initial, msg, emit).model
    assert_true(other == test_file_input(next, 1))
  }
  let opened = @application.update(
      initial,
      Review(
        OpenInlineDraft(0, {
          path: "a.mbt",
          side: Right,
          line: 1,
          position: Some(2),
        }),
      ),
      emit,
    ).model
  let typed = @application.update(
      opened,
      Review(DraftBodyChanged("body")),
      emit,
    ).model
  assert_true(test_file_input(opened, 1) == test_file_input(typed, 1))
  assert_false(test_file_input(opened, 0) == test_file_input(typed, 0))
  let layout = @application.update(initial, Ui(SelectView(Unified)), emit).model
  assert_false(other == test_file_input(layout, 1))
}

///|
test "sign-in dialog changes invalidate only Discussion" {
  let model = pull_region_model()
  let projection = RegionProjection::new()
  let before = projection.inputs(model)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let opened = @application.update(
      model,
      Ui(OpenSignIn(model.generation, Comment(0), None)),
      emit,
    ).model
  let after = projection.inputs(opened)
  assert_eq(before.length(), after.length())
  for index in 0..<before.length() {
    assert_true(before[index].0 == after[index].0)
    assert_eq(before[index].1 != after[index].1, before[index].0 is Discussion)
  }
}

///|
test "merge action changes invalidate navigation and the independent merge region" {
  assert_false(
    RegionProjection::new()
    .inputs(region_model())
    .any(entry => entry.0 is PullMergeStatus),
  )
  let model = {
    ..pull_region_model(),
    auth: SignedIn(login=Some("alice"), user_id=Some("1"), install_url=None),
  }
  let projection = RegionProjection::new()
  let before = projection.inputs(model)
  let status : @protocol.ApiPullMergeStatus = {
    base_sha: "1111111111111111111111111111111111111111",
    head_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    open: true,
    draft: false,
    merged: false,
    mergeable: Some(true),
    rebaseable: Some(true),
    mergeable_state: "clean",
    ci_summary: Some(Success),
    ci_checks: [],
    ci_warnings: [],
  }
  let changed = {
    ..model,
    pull_merge: { ..model.pull_merge, status: Some(status), },
  }
  let after = projection.inputs(changed)
  assert_eq(before.length(), after.length())
  for index in 0..<before.length() {
    let (before_region, before_input) = before[index]
    let (after_region, after_input) = after[index]
    assert_true(before_region == after_region)
    if before_region is (PullMergeStatus | Navigation) {
      assert_false(before_input == after_input)
    } else {
      assert_true(before_input == after_input)
    }
  }
  // Error messages and CI details stay local when the button state is unchanged.
  let ci_changed = {
    ..changed,
    pull_merge: {
      ..changed.pull_merge,
      status: Some({
        ..status,
        ci_summary: Some(Failure),
        ci_warnings: ["CI results are incomplete"],
      }),
      error: Some("Try again"),
      serial: changed.pull_merge.serial + 1,
      poll_scheduled: true,
    },
  }
  let after_ci = projection.inputs(ci_changed)
  for index in 0..<after.length() {
    assert_eq(
      after[index].1 != after_ci[index].1,
      after[index].0 is PullMergeStatus,
    )
  }
}

///|
test "draft edits reuse canonical patch, review rows and visible projection; layout only reprojects" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let initial = region_model()
  let cache = FileDerivation::new()
  ignore(region_view(File(test_file_input(initial, 0)), emit, cache))
  let patch = cache.patch
  let projection = cache.projection
  let rows = cache.rows.copy()
  assert_false(rows.is_empty())
  let opened = @application.update(
      initial,
      Review(
        OpenInlineDraft(0, {
          path: "a.mbt",
          side: Right,
          line: 1,
          position: Some(2),
        }),
      ),
      emit,
    ).model
  let typed = @application.update(
      opened,
      Review(DraftBodyChanged("some text")),
      emit,
    ).model
  ignore(region_view(File(test_file_input(typed, 0)), emit, cache))
  assert_true(@identity.same(patch, cache.patch))
  assert_true(@identity.same(projection, cache.projection))
  for key, row in rows {
    assert_true(@identity.same(row.items, cache.rows[key].items))
  }
  let layout = @application.update(typed, Ui(SelectView(Unified)), emit).model
  ignore(region_view(File(test_file_input(layout, 0)), emit, cache))
  assert_false(@identity.same(projection, cache.projection))
  assert_true(@identity.same(patch, cache.patch))
  for key, row in rows {
    assert_true(@identity.same(row.items, cache.rows[key].items))
  }
}
