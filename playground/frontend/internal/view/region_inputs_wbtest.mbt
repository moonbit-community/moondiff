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
    restore_pending: false,
    last_authenticated_user_id: None,
    home: @application.HomeState::new(),
    viewed: @application.ViewedState::new(),
    pull_merge: @application.PullMergeState::new(),
    review,
    range: None,
  }
}

///|
fn test_file_input(model : Model, index : Int) -> FileInput {
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
test "merge status changes invalidate only the independent merge region" {
  assert_false(
    RegionProjection::new()
    .inputs(region_model())
    .any(entry => entry.0 is PullMergeStatus),
  )
  let model = pull_region_model()
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
    if before_region is PullMergeStatus {
      assert_false(before_input == after_input)
    } else {
      assert_true(before_input == after_input)
    }
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
