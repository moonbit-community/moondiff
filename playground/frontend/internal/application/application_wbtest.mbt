///|
extern "js" fn read_fixture(path : String) -> String =
  #| (path) => require("node:fs").readFileSync(path, "utf8")

///|
fn fixture_file(
  filename : String,
  status : String,
  previous_filename? : String,
) -> ApiFile {
  {
    filename,
    previous_filename,
    status,
    additions: 1,
    deletions: 2,
    changes: 3,
    patch: None,
  }
}

///|
test "stale commit responses are discarded by generation" {
  let model = Model::{
    viewed: empty_viewed_state(0),
    input: "https://github.com/a/b/commit/abcdef1",
    generation: 2,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Idle,
    route: None,
    file_tree: initial_file_tree_state(),
    auth: Anonymous(None),
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: None,
    review: initial_review_state(),
  }
  let fixture = decode_commit(read_fixture("testdata/github/root_commit.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update_load(model, CommitPageLoaded(1, 1, Ok(fixture)), emit)
  assert_true(after == model)
}

///|
fn pull_test_model(
  reference : CommitRef,
  generation : Int,
  phase : Phase,
) -> Model {
  {
    viewed: empty_viewed_state(0),
    input: canonical_github_url(reference),
    generation,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase,
    route: Some(reference),
    file_tree: initial_file_tree_state(),
    auth: Anonymous(None),
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: None,
    review: initial_review_state(),
  }
}

///|
test "pull metadata starts a pinned snapshot and enforces the file limit" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = pull_test_model(
    reference,
    8,
    LoadingPullMetadata(reference~, attempt=0),
  )
  let (stale_generation, _) = update_load(
    loading,
    PullMetadataLoaded(7, 0, Ok(pull)),
    emit,
  )
  assert_true(stale_generation == loading)
  let (stale_attempt, _) = update_load(
    loading,
    PullMetadataLoaded(8, 1, Ok(pull)),
    emit,
  )
  assert_true(stale_attempt == loading)
  let (started, _) = update_load(
    loading,
    PullMetadataLoaded(8, 0, Ok(pull)),
    emit,
  )
  guard started.phase
    is LoadingPullSnapshot(
      attempt=0,
      metadata=pinned,
      compare=None,
      page=1,
      files=[],
      ..
    ) else {
    fail("expected a pinned pull request snapshot")
  }
  assert_eq(pinned.base.sha, pull.base.sha)
  assert_eq(pinned.head.sha, pull.head.sha)

  let (over_limit, _) = update_load(
    loading,
    PullMetadataLoaded(8, 0, Ok({ ..pull, changed_files: 3_001, })),
    emit,
  )
  guard over_limit.phase is LoadFailed(limit_message) else {
    fail("expected an over-limit pull request to fail")
  }
  assert_true(limit_message.contains("3,000-file API limit"))
}

///|
test "pull compare and files can arrive out of order but wait for validation" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let compare = decode_compare(
    read_fixture("testdata/github/pull_compare.json"),
  )
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = pull_test_model(
    reference,
    7,
    LoadingPullSnapshot(
      reference~,
      attempt=0,
      metadata=pull,
      compare=None,
      page=1,
      files=[],
    ),
  )
  let (wrong_page, _) = update_load(
    loading,
    PullFilesPageLoaded(7, 0, 2, Ok(files)),
    emit,
  )
  assert_true(wrong_page == loading)
  let (wrong_attempt, _) = update_load(
    loading,
    PullCompareLoaded(7, 1, Ok(compare)),
    emit,
  )
  assert_true(wrong_attempt == loading)
  let (after_files, _) = update_load(
    loading,
    PullFilesPageLoaded(7, 0, 1, Ok(files)),
    emit,
  )
  guard after_files.phase
    is LoadingPullSnapshot(page=0, compare=None, files=loaded_files, ..) else {
    fail("expected files to wait for the compare response")
  }
  assert_eq(loaded_files.map(file => file.filename), [
    "src/first.mbt", "README.md",
  ])
  let (early_validation, _) = update_load(
    after_files,
    PullValidationLoaded(7, 0, Ok(pull)),
    emit,
  )
  assert_true(early_validation == after_files)
  let (validating, _) = update_load(
    after_files,
    PullCompareLoaded(7, 0, Ok(compare)),
    emit,
  )
  assert_true(validating.phase is ValidatingPullSnapshot(attempt=0, ..))
  let verified = { ..pull, title: "Verified pull title", additions: 11, }
  let (shown, _) = update_load(
    validating,
    PullValidationLoaded(7, 0, Ok(verified)),
    emit,
  )
  guard shown.phase is Showing(view) else {
    fail("expected the validated pull request to be shown")
  }
  assert_eq(view.sha, "cccccccccccccccccccccccccccccccccccccccc")
  assert_eq(view.parent_sha, Some("9999999999999999999999999999999999999999"))
  assert_eq(view.message, "Verified pull title")
  assert_eq(view.stats.additions, 11)
  assert_eq(view.total_files, 2)
  assert_eq(view.files.map(file => file.file.filename), [
    "src/first.mbt", "README.md",
  ])
}

///|
test "a changed pull head retries once and discards the old attempt" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let compare = decode_compare(
    read_fixture("testdata/github/pull_compare.json"),
  )
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let validating = pull_test_model(
    reference,
    9,
    ValidatingPullSnapshot(
      reference~,
      attempt=0,
      metadata=pull,
      compare~,
      files~,
    ),
  )
  let latest = {
    ..pull,
    title: "Latest pull title",
    head: { sha: "dddddddddddddddddddddddddddddddddddddddd", repo: None, },
    additions: 13,
  }
  assert_eq(latest.changed_files, pull.changed_files)
  let (retrying, _) = update_load(
    validating,
    PullValidationLoaded(9, 0, Ok(latest)),
    emit,
  )
  guard retrying.phase
    is LoadingPullSnapshot(
      attempt=1,
      metadata=retry_metadata,
      compare=None,
      page=1,
      files=[],
      ..
    ) else {
    fail("expected the latest metadata to start one retry")
  }
  assert_eq(retry_metadata.head.sha, latest.head.sha)
  let (stale_generation, _) = update_load(
    retrying,
    PullCompareLoaded(8, 1, Ok(compare)),
    emit,
  )
  assert_true(stale_generation == retrying)
  let (stale_compare, _) = update_load(
    retrying,
    PullCompareLoaded(9, 0, Ok(compare)),
    emit,
  )
  assert_true(stale_compare == retrying)
  let (stale_files, _) = update_load(
    retrying,
    PullFilesPageLoaded(9, 0, 1, Ok(files)),
    emit,
  )
  assert_true(stale_files == retrying)
  let (stale_files_generation, _) = update_load(
    retrying,
    PullFilesPageLoaded(8, 1, 1, Ok(files)),
    emit,
  )
  assert_true(stale_files_generation == retrying)
  let (stale_validation, _) = update_load(
    retrying,
    PullValidationLoaded(9, 0, Ok(latest)),
    emit,
  )
  assert_true(stale_validation == retrying)

  let latest_compare : ApiCompare = {
    merge_base_commit: { sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", },
  }
  let (with_compare, _) = update_load(
    retrying,
    PullCompareLoaded(9, 1, Ok(latest_compare)),
    emit,
  )
  let (validating_latest, _) = update_load(
    with_compare,
    PullFilesPageLoaded(9, 1, 1, Ok(files)),
    emit,
  )
  assert_true(validating_latest.phase is ValidatingPullSnapshot(attempt=1, ..))
  let (stale_validation_generation, _) = update_load(
    validating_latest,
    PullValidationLoaded(8, 1, Ok(latest)),
    emit,
  )
  assert_true(stale_validation_generation == validating_latest)
  let (shown, _) = update_load(
    validating_latest,
    PullValidationLoaded(9, 1, Ok(latest)),
    emit,
  )
  guard shown.phase is Showing(view) else {
    fail("expected the retried snapshot to be shown")
  }
  assert_eq(view.sha, latest.head.sha)
  assert_eq(view.parent_sha, Some(latest_compare.merge_base_commit.sha))
  assert_eq(view.message, "Latest pull title")
  assert_eq(view.stats.additions, 13)
}

///|
test "a pull request that changes during both attempts fails explicitly" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let compare = decode_compare(
    read_fixture("testdata/github/pull_compare.json"),
  )
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
  let validating = pull_test_model(
    reference,
    10,
    ValidatingPullSnapshot(
      reference~,
      attempt=1,
      metadata=pull,
      compare~,
      files~,
    ),
  )
  let changed_again = {
    ..pull,
    base: { sha: "ffffffffffffffffffffffffffffffffffffffff", repo: None, },
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (failed, _) = update_load(
    validating,
    PullValidationLoaded(10, 1, Ok(changed_again)),
    emit,
  )
  assert_true(failed.phase is LoadFailed(PULL_CHANGED_ERROR))
}

///|
test "incomplete pull pagination retries once then keeps the incomplete error" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let compare = decode_compare(
    read_fixture("testdata/github/pull_compare.json"),
  )
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = pull_test_model(
    reference,
    11,
    LoadingPullSnapshot(
      reference~,
      attempt=0,
      metadata=pull,
      compare=Some(compare),
      page=1,
      files=[],
    ),
  )
  let (validating, _) = update_load(
    loading,
    PullFilesPageLoaded(11, 0, 1, Ok([files[0]])),
    emit,
  )
  assert_true(validating.phase is ValidatingPullSnapshot(attempt=0, ..))
  let (retrying, _) = update_load(
    validating,
    PullValidationLoaded(11, 0, Ok(pull)),
    emit,
  )
  assert_true(retrying.phase is LoadingPullSnapshot(attempt=1, ..))

  let final_validation = {
    ..retrying,
    phase: ValidatingPullSnapshot(
      reference~,
      attempt=1,
      metadata=pull,
      compare~,
      files=[files[0]],
    ),
  }
  let (incomplete, _) = update_load(
    final_validation,
    PullValidationLoaded(11, 1, Ok(pull)),
    emit,
  )
  guard incomplete.phase is LoadFailed(message) else {
    fail("expected a stable incomplete snapshot to fail")
  }
  assert_true(message.contains("returned 1 files"))
  assert_true(message.contains("metadata reports 2"))
}

///|
test "stale source responses are discarded by generation" {
  let view = diff_test_view([fixture_file("src/main.mbt", "modified")])
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = {
    ..initial_model(),
    generation: 7,
    phase: Showing(view),
    route: Some(view.reference),
  }
  let (after, _) = update_load(
    model,
    SourceLoaded(6, 0, New, Ok(("text/plain", @utf8.encode("stale")))),
    emit,
  )
  assert_true(after == model)
}

///|
fn diff_test_view(files : Array[ApiFile]) -> ChangeView raise {
  let fixture = decode_commit(read_fixture("testdata/github/commit_page1.json"))
  let view = finish_commit(
    commit_reference("example", "project", fixture.sha),
    { owner: "example", repo: "project", },
    fixture,
    files,
  )
  view
}

///|
fn diff_test_model(view : ChangeView) -> Model {
  {
    viewed: empty_viewed_state(0),
    input: "",
    generation: 9,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    file_tree: initial_file_tree_state(),
    auth: Anonymous(None),
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: None,
    review: initial_review_state(),
  }
}

///|
fn ready_test_file(
  file : ApiFile,
  old : Array[String],
  new : Array[String],
  expanded? : Bool = true,
) -> FileState {
  {
    file,
    diff_mode: file_diff_mode(file),
    expanded,
    collapsed_sections: [],
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: DiffCache::empty(),
  }
}

///|
fn changed_file_tree_state() -> FileTreeState {
  {
    drawer_open: true,
    search_open: true,
    search_query: "src",
    selected_statuses: ["modified"],
    collapsed_directories: ["src"],
    selected_file_index: Some(3),
    preferred_width: 512,
  }
}

///|
test "file tree width defaults changes and clamps to absolute limits" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let initial = initial_model()
  assert_eq(initial.file_tree.preferred_width, 240)

  let (changed, _) = update_ui(initial, FileTreeWidthChanged(486), emit)
  assert_eq(changed.file_tree.preferred_width, 486)
  let (minimum, _) = update_ui(changed, FileTreeWidthChanged(120), emit)
  assert_eq(minimum.file_tree.preferred_width, 240)
  let (maximum, _) = update_ui(minimum, FileTreeWidthChanged(900), emit)
  assert_eq(maximum.file_tree.preferred_width, 640)

  // A new model is what a full page load initializes.
  assert_eq(initial_model().file_tree.preferred_width, 240)
}

///|
test "file tree UI state toggles filters and closing search clears its query" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = { ..initial_model(), file_tree: changed_file_tree_state(), }
  let (closed_search, _) = update_ui(model, ToggleFileTreeSearch, emit)
  assert_false(closed_search.file_tree.search_open)
  assert_eq(closed_search.file_tree.search_query, "")
  assert_true(closed_search.file_tree.drawer_open)

  let (opened_search, _) = update_ui(closed_search, ToggleFileTreeSearch, emit)
  assert_true(opened_search.file_tree.search_open)
  let (queried, _) = update_ui(
    opened_search,
    FileTreeSearchChanged("README"),
    emit,
  )
  assert_eq(queried.file_tree.search_query, "README")

  let (added_status, _) = update_ui(
    queried,
    ToggleFileTreeStatus("added"),
    emit,
  )
  assert_eq(added_status.file_tree.selected_statuses, ["modified", "added"])
  let (removed_status, _) = update_ui(
    added_status,
    ToggleFileTreeStatus("modified"),
    emit,
  )
  assert_eq(removed_status.file_tree.selected_statuses, ["added"])

  let (expanded_directory, _) = update_ui(
    removed_status,
    ToggleFileTreeDirectory("src"),
    emit,
  )
  assert_true(expanded_directory.file_tree.collapsed_directories.is_empty())
  let (collapsed_directory, _) = update_ui(
    expanded_directory,
    ToggleFileTreeDirectory("src"),
    emit,
  )
  assert_eq(collapsed_directory.file_tree.collapsed_directories, ["src"])

  let (closed_drawer, _) = update_ui(
    collapsed_directory,
    CloseFileTreeDrawer,
    emit,
  )
  assert_false(closed_drawer.file_tree.drawer_open)
}

///|
test "file tree drawer remains narrow and exits at the desktop breakpoint" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = { ..initial_model(), file_tree: changed_file_tree_state(), }
  let (narrow, _) = update_ui(model, FileTreeViewportChanged(767), emit)
  assert_true(narrow == model)

  let (desktop, _) = update_ui(model, FileTreeViewportChanged(768), emit)
  assert_false(desktop.file_tree.drawer_open)
  assert_true(desktop.file_tree.search_open)
  assert_eq(desktop.file_tree.search_query, "src")
  assert_eq(desktop.file_tree.selected_statuses, ["modified"])
  assert_eq(desktop.file_tree.collapsed_directories, ["src"])
  assert_eq(desktop.file_tree.selected_file_index, Some(3))
}

///|
test "file tree UI state resets preserve the preferred width" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let reference = commit_reference("owner", "repo", "abcdef1")
  let dirty = { ..initial_model(), file_tree: changed_file_tree_state(), }
  let (loading, _) = begin_change_load(dirty, reference, emit)
  assert_true(
    loading.file_tree == { ..initial_file_tree_state(), preferred_width: 512, },
  )

  let showing = {
    ..dirty,
    generation: 4,
    route: Some(reference),
    phase: Showing(diff_test_view([fixture_file("README.md", "modified")])),
  }
  let landing_url = try! @url.parse("http://localhost/")
  let (landing, _) = update_ui(showing, RouteChanged(landing_url), emit)
  assert_true(landing.phase is Idle)
  assert_true(
    landing.file_tree == { ..initial_file_tree_state(), preferred_width: 512, },
  )

  let failing = {
    ..dirty,
    generation: 6,
    phase: LoadingCommit(
      reference~,
      repository=reference_repository(reference),
      page=1,
      first=None,
      files=[],
    ),
  }
  let (failed, _) = update_load(
    failing,
    CommitPageLoaded(
      6,
      1,
      Err(GitHubRequestError::GitHubRequestError("load failed")),
    ),
    emit,
  )
  assert_true(failed.phase is LoadFailed(_))
  assert_true(
    failed.file_tree == { ..initial_file_tree_state(), preferred_width: 512, },
  )
}

///|
test "opening a tree file selects expands lazy loads and reuses cached sources" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let lazy_file = fixture_file("docs/guide.md", "modified")
  let lazy_view = diff_test_view([lazy_file])
  let lazy_model = {
    ..diff_test_model(lazy_view),
    file_tree: { ..initial_file_tree_state(), drawer_open: true, },
  }
  let (stale, _) = update_load(
    lazy_model,
    OpenFile(lazy_model.generation - 1, 0),
    emit,
  )
  assert_true(stale == lazy_model)

  let (opened, _) = update_load(
    lazy_model,
    OpenFile(lazy_model.generation, 0),
    emit,
  )
  assert_eq(opened.file_tree.selected_file_index, Some(0))
  assert_false(opened.file_tree.drawer_open)
  guard opened.phase is Showing(opened_view) else {
    fail("expected the selected file to stay visible")
  }
  assert_true(opened_view.files[0].expanded)
  assert_true(opened_view.files[0].old_side is Loading)
  assert_true(opened_view.files[0].new_side is Loading)

  let ready = ensure_file_document(
    ready_test_file(lazy_file, ["old"], ["new"], expanded=false),
    LexicalAlgorithm,
  )
  guard ready.diff_cache.get(Line) is Some(cached) else {
    fail("expected a cached line diff")
  }
  let cached_view = set_file_state(diff_test_view([lazy_file]), 0, ready)
  let cached_model = {
    ..diff_test_model(cached_view),
    file_tree: { ..initial_file_tree_state(), drawer_open: true, },
  }
  let (reopened, _) = update_load(
    cached_model,
    OpenFile(cached_model.generation, 0),
    emit,
  )
  guard reopened.phase is Showing(reopened_view) else {
    fail("expected the cached file to open")
  }
  assert_true(reopened_view.files[0].expanded)
  assert_true(reopened_view.files[0].old_side is Ready(_))
  assert_true(reopened_view.files[0].new_side is Ready(_))
  assert_true(reopened_view.files[0].diff_cache.get(Line) == Some(cached))

  let (selected_again, _) = update_load(
    reopened,
    OpenFile(reopened.generation, 0),
    emit,
  )
  assert_true(selected_again.phase == reopened.phase)
  assert_eq(selected_again.file_tree.selected_file_index, Some(0))
}

///|
fn all_moonbit_cache_keys() -> Array[CacheKey] {
  [
    MoonBit(LexicalAlgorithm, false, false),
    MoonBit(LexicalAlgorithm, true, false),
    MoonBit(LexicalAlgorithm, false, true),
    MoonBit(LexicalAlgorithm, true, true),
    MoonBit(AstAlgorithm, false, false),
    MoonBit(AstAlgorithm, true, false),
    MoonBit(AstAlgorithm, false, true),
    MoonBit(AstAlgorithm, true, true),
  ]
}

///|
test "Lexical is the default and algorithm selection is not part of routes" {
  let model = initial_model()
  assert_true(model.diff_algorithm is LexicalAlgorithm)
  assert_true(model.ignore_comments)
  assert_true(model.ignore_tests)
  let reference = commit_reference("owner", "repo", "abcdef1")
  assert_eq(playground_route(reference), "/owner/repo/commit/abcdef1")
  assert_false(playground_route(reference).contains("algorithm"))
  assert_false(playground_route(reference).contains("ignore"))
}

///|
test "algorithm switching fills the second cache and reuses the first" {
  let file = fixture_file("src/format.mbt", "modified")
  let lexical_key = CacheKey::MoonBit(LexicalAlgorithm, false, false)
  let ast_key = CacheKey::MoonBit(AstAlgorithm, false, false)
  let lexical_file = ensure_file_document(
    ready_test_file(file, ["fn format() { 1 }"], ["fn format() {", "  1", "}"]),
    LexicalAlgorithm,
  )
  guard lexical_file.diff_cache.get(lexical_key) is Some(lexical) else {
    fail("expected lexical cache")
  }
  assert_true(lexical_file.diff_cache.get(ast_key) is None)
  let view = set_file_state(diff_test_view([file]), 0, lexical_file)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (switched, _) = update_ui(
    diff_test_model(view),
    SelectDiffAlgorithm(AstAlgorithm),
    emit,
  )
  assert_true(switched.diff_algorithm is AstAlgorithm)
  guard switched.phase is Showing(changed_view) else {
    fail("expected commit to remain visible")
  }
  let changed = changed_view.files[0]
  assert_true(changed.diff_cache.get(lexical_key) == Some(lexical))
  guard changed.diff_cache.get(ast_key) is Some(ast) else {
    fail("expected AST cache")
  }
  guard ast is MoonBit(status~, ..) else { fail("expected MoonBit cache") }
  assert_true(status is NoStructuralChanges)
  let (switched_back, _) = update_ui(
    switched,
    SelectDiffAlgorithm(LexicalAlgorithm),
    emit,
  )
  guard switched_back.phase is Showing(restored_view) else {
    fail("expected commit to remain visible")
  }
  assert_true(restored_view.files[0].diff_cache == changed.diff_cache)
  assert_true(
    restored_view.files[0].diff_cache.get(lexical_key) == Some(lexical),
  )
}

///|
test "ignore comments has independent algorithm caches" {
  let file = fixture_file("src/comments.mbt", "modified")
  let ready = ready_test_file(
    file,
    ["fn value() -> Int {", "  1 // old", "}"],
    ["fn value() -> Int {", "  1 // new", "}"],
  )
  let cached = ensure_file_document(
    ensure_file_document(
      ensure_file_document(
        ensure_file_document(ready, LexicalAlgorithm),
        LexicalAlgorithm,
        ignore_comments=true,
      ),
      AstAlgorithm,
    ),
    AstAlgorithm,
    ignore_comments=true,
  )
  assert_true(
    cached.diff_cache.get(MoonBit(LexicalAlgorithm, false, false)) is Some(_),
  )
  let filtered_key = CacheKey::MoonBit(LexicalAlgorithm, true, false)
  assert_true(cached.diff_cache.get(filtered_key) is Some(_))
  assert_true(
    cached.diff_cache.get(MoonBit(AstAlgorithm, false, false)) is Some(_),
  )
  assert_true(
    cached.diff_cache.get(MoonBit(AstAlgorithm, true, false)) is Some(_),
  )
  guard cached.diff_cache.get(filtered_key) is Some(filtered) else {
    fail("expected filtered lexical cache")
  }
  guard filtered is MoonBit(document=Whole(fragment), status=IgnoredOnly, ..) else {
    fail("expected an ignored-only semantic cache")
  }
  assert_true(fragment.document.hunks.is_empty())

  let view = set_file_state(diff_test_view([file]), 0, cached)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (toggled, _) = update_ui(
    diff_test_model(view),
    ToggleIgnoreComments,
    emit,
  )
  assert_true(toggled.ignore_comments)
  assert_true(toggled.diff_algorithm is LexicalAlgorithm)
  guard toggled.phase is Showing(toggled_view) else {
    fail("expected commit to remain visible")
  }
  assert_true(toggled_view.files[0].diff_cache.get(filtered_key) is Some(_))
}

///|
test "ignore comments survives commit navigation but stays out of routes" {
  let reference = commit_reference("owner", "repo", "abcdef1")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let fixture = decode_commit(read_fixture("testdata/github/root_commit.json"))
  let loading = {
    ..initial_model(),
    generation: 1,
    ignore_comments: true,
    route: Some(reference),
    phase: LoadingCommit(
      reference~,
      repository=reference_repository(reference),
      page=1,
      first=None,
      files=[],
    ),
  }
  let (loaded, _) = update_load(
    loading,
    CommitPageLoaded(1, 1, Ok(fixture)),
    emit,
  )
  assert_true(loaded.ignore_comments)
  assert_true(loaded.phase is Showing(_))
  assert_false(playground_route(reference).contains("ignore"))
}

///|
test "ignore tests toggles independently and survives navigation without routes" {
  let file = fixture_file("src/tests.mbt", "modified")
  let ready = ready_test_file(file, ["test \"sample\" { old_value() }"], [
    "test \"sample\" { new_value() }",
  ])
  let view = set_file_state(diff_test_view([file]), 0, ready)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (toggled, _) = update_ui(diff_test_model(view), ToggleIgnoreTests, emit)
  assert_true(toggled.ignore_tests)
  assert_false(toggled.ignore_comments)
  guard toggled.phase is Showing(toggled_view) else {
    fail("expected commit to remain visible")
  }
  assert_true(
    toggled_view.files[0].diff_cache.get(MoonBit(LexicalAlgorithm, false, true))
    is Some(_),
  )

  let reference = commit_reference("owner", "repo", "abcdef1")
  let fixture = decode_commit(read_fixture("testdata/github/root_commit.json"))
  let loading = {
    ..toggled,
    generation: 1,
    route: Some(reference),
    phase: LoadingCommit(
      reference~,
      repository=reference_repository(reference),
      page=1,
      first=None,
      files=[],
    ),
  }
  let (loaded, _) = update_load(
    loading,
    CommitPageLoaded(1, 1, Ok(fixture)),
    emit,
  )
  assert_true(loaded.ignore_tests)
  assert_false(playground_route(reference).contains("ignore"))
}

///|
test "new source invalidates every MoonBit filter cache" {
  let file = fixture_file("src/change.mbt", "modified")
  let mut cached = ready_test_file(file, ["fn f() { old() }"], [
    "fn f() { new() }",
  ])
  let algorithms : Array[DiffAlgorithm] = [LexicalAlgorithm, AstAlgorithm]
  for algorithm in algorithms {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        cached = ensure_file_document(
          cached,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
      }
    }
  }
  for key in all_moonbit_cache_keys() {
    assert_true(cached.diff_cache.get(key) is Some(_))
  }
  let view = set_file_state(diff_test_view([file]), 0, cached)
  let model = {
    ..diff_test_model(view),
    diff_algorithm: AstAlgorithm,
    ignore_comments: true,
    ignore_tests: true,
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (updated, _) = update_load(
    model,
    SourceLoaded(
      model.generation,
      0,
      New,
      Ok(("text/plain", @utf8.encode("fn f() { newest() }"))),
    ),
    emit,
  )
  guard updated.phase is Showing(updated_view) else { fail("expected commit") }
  let current_key = CacheKey::MoonBit(AstAlgorithm, true, true)
  for key in all_moonbit_cache_keys() {
    if key == current_key {
      assert_true(updated_view.files[0].diff_cache.get(key) is Some(_))
    } else {
      assert_true(updated_view.files[0].diff_cache.get(key) is None)
    }
  }
  assert_true(updated_view.files[0].diff_cache.get(Line) is None)
}

///|
test "HTTP request errors retain diagnostics and format unknown codes neutrally" {
  let error : Error = HttpRequestError::HttpRequestError(
    status=400,
    code="invalid_arguments",
    detail="Missing RPC argument: sha",
  )
  guard error is HttpRequestError::HttpRequestError(status~, code~, detail~) else {
    fail("expected a structured extension error")
  }
  assert_eq(status, 400)
  assert_eq(code, "invalid_arguments")
  assert_eq(detail, "Missing RPC argument: sha")
  assert_eq(
    error_message(error, true),
    "Moondiff HTTP request failed (status 400, invalid_arguments): Missing RPC argument: sha",
  )
}

///|
test "HTTP request codes retain actionable GitHub guidance" {
  assert_eq(
    comment_failure_message(
      HttpRequestError::HttpRequestError(
        status=403,
        code="rate_limit",
        detail="API rate limit exceeded",
      ),
    ),
    "GitHub API rate limit exceeded. Sign in or try again after the reset time.",
  )
  assert_eq(
    comment_failure_message(
      HttpRequestError::HttpRequestError(
        status=401,
        code="authentication_required",
        detail="Bad credentials",
      ),
    ),
    "Your GitHub session expired. Sign in again, then retry.",
  )
  assert_eq(
    comment_failure_message(
      HttpRequestError::HttpRequestError(
        status=404,
        code="not_found_or_not_installed",
        detail="Not Found",
      ),
    ),
    "GitHub could not access this repository. Sign in and install the GitHub App for private repositories.",
  )
  assert_eq(
    comment_failure_message(
      HttpRequestError::HttpRequestError(
        status=403,
        code="permission_denied",
        detail="Resource not accessible by integration",
      ),
    ),
    "GitHub denied this action. Install the app for this repository and check its Contents and Pull requests permissions.",
  )
  assert_eq(
    comment_failure_message(
      HttpRequestError::HttpRequestError(
        status=422,
        code="invalid_comment_anchor",
        detail="Validation Failed",
      ),
    ),
    "GitHub rejected this comment anchor. Refresh the diff and choose the line again.",
  )
  assert_eq(
    error_message(
      GitHubRequestError::GitHubRequestError(
        "GitHub request failed: HTTP 403 API rate limit exceeded",
      ),
      true,
    ),
    "GitHub API rate limit exceeded. Sign in or try again after the reset time.",
  )
}

///|
fn review_test_view(target? : ChangeTarget = PullRequest("17")) -> ChangeView {
  let reference = CommitRef::{ owner: "upstream", repo: "project", target, }
  let repository = RepositoryRef::{ owner: "upstream", repo: "project", }
  let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let view = finish_change(
    reference,
    Some({ repository, sha: "1111111111111111111111111111111111111111", }),
    { repository, sha: head, },
    "Review fixture",
    canonical_github_url(reference),
    { additions: 1, deletions: 1, total: 2, },
    [
      {
        filename: "src/main.mbt",
        previous_filename: None,
        status: "modified",
        additions: 1,
        deletions: 1,
        changes: 2,
        patch: Some("@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail"),
      },
    ],
  )
  {
    ..view,
    pull_snapshot: if target is PullRequest(_) {
      Some(review_test_pull())
    } else {
      None
    },
  }
}

///|
fn review_test_pull() -> ApiPull {
  {
    title: "Review fixture",
    html_url: "https://github.com/upstream/project/pull/17",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "upstream/project", }),
    },
    head: {
      sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repo: Some({ full_name: "upstream/project", }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
}

///|
fn review_test_refresh(
  model : Model,
  bundle : ApiCommentBundle,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let pull = review_test_pull()
  let pending = with_review(
    model,
    review_fixture(model.review, refresh=RefreshList(Some(pull))),
  )
  let (loaded, _) = update_review(
    pending,
    CommentsLoaded(model.generation, pending.review.refresh_id, Ok(bundle)),
    emit,
  )
  update_review(
    loaded,
    CommentsValidated(model.generation, pending.review.refresh_id, Ok(pull)),
    emit,
  )
}

///|
fn review_test_model(auth : AuthStatus) -> Model {
  let view = review_test_view()
  {
    ..initial_model(),
    input: canonical_github_url(view.reference),
    generation: 5,
    phase: Showing(view),
    route: Some(view.reference),
    auth,
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: match auth {
      SignedIn(user_id~, ..) => user_id
      _ => None
    },
    review: review_fixture(
      initial_review_state(),
      deletion=None,
      deleted=[],
      comments=CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
      draft=None,
      stage=initial_review_state().submission(),
      can_comment=auth is SignedIn(..),
      login=match auth {
        SignedIn(login~, ..) => login
        _ => None
      },
    ),
  }
}

///|
fn authentication_required_error() -> Error {
  HttpRequestError::HttpRequestError(
    status=401,
    code="authentication_required",
    detail="Bad credentials",
  )
}

///|
test "only signed-in reviews can open comment drafts" {
  let view = review_test_view()
  let anchor = canonical_anchor(
    parse_canonical_patch("src/main.mbt", view.files[0].file.patch),
    Right,
    2,
  ).unwrap()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let auths : Array[AuthStatus] = [
    Anonymous(None),
    AuthChecking,
    Anonymous(None),
    Authorizing(starting_device("test-attempt-00000000"), ""),
    AuthFailed("authentication failed"),
  ]
  for auth in auths {
    let model = review_test_model(auth)
    assert_false(review_can_comment(model.review))
    let messages : Array[ReviewMsg] = [
      OpenOverallDraft,
      OpenInlineDraft(0, anchor),
      OpenReplyDraft(Int64::from_int(20)),
    ]
    for msg in messages {
      let (blocked, _) = update_review(model, msg, emit)
      assert_true(blocked == model)
    }
  }

  let signed_in = review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
  assert_true(review_can_comment(signed_in.review))
  let (overall, _) = update_review(signed_in, OpenOverallDraft, emit)
  guard overall.review.draft() is Some(overall_draft) else {
    fail("expected an overall draft")
  }
  assert_true(overall_draft.kind is OverallDraft)
  let (inline, _) = update_review(signed_in, OpenInlineDraft(0, anchor), emit)
  guard inline.review.draft() is Some(inline_draft) else {
    fail("expected an inline draft")
  }
  assert_true(
    inline_draft.kind is InlineDraft(0, selected) && selected == anchor,
  )
  let signed_in = review_reply_test_model()
  let comment_id = Int64::from_int(20)
  let (reply, _) = update_review(signed_in, OpenReplyDraft(comment_id), emit)
  guard reply.review.draft() is Some(reply_draft) else {
    fail("expected a reply draft")
  }
  assert_true(
    reply_draft.kind is ReplyDraft(selected) && selected == comment_id,
  )
}

///|
test "submitting a retained draft still requires sign-in" {
  let model = review_test_model(Anonymous(None))
  let with_draft = with_review(
    model,
    review_state_with_draft(
      model.review,
      Some({
        snapshot: None,
        id: { generation: 0, sequence: 0, },
        kind: OverallDraft,
        body: "comment body",
        submitting: false,
        error: None,
      }),
    ),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (blocked, _) = update_review(with_draft, SubmitDraft, emit)
  guard blocked.review.draft() is Some(draft) else {
    fail("expected the blocked draft to be retained")
  }
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("Sign in with GitHub"))
}

///|
test "comment loading authentication failure signs out and preserves the draft" {
  let model = review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
  let draft = CommentDraft::{
    snapshot: None,
    id: { generation: 0, sequence: 0, },
    kind: OverallDraft,
    body: "keep this draft",
    submitting: false,
    error: None,
  }
  let with_draft = with_review(
    model,
    review_state_with_draft(model.review, Some(draft)),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (failed, _) = update_review(
    with_review(
      with_draft,
      review_fixture(
        with_draft.review,
        refresh=RefreshList(Some(review_test_pull())),
      ),
    ),
    CommentsLoaded(
      5,
      with_draft.review.refresh_id + 1,
      Err(authentication_required_error()),
    ),
    emit,
  )
  guard failed.auth is AuthFailed(auth_message) else {
    fail("expected comment loading to invalidate authentication")
  }
  assert_true(auth_message.contains("expired"))
  assert_false(review_can_comment(failed.review))
  assert_true(failed.review.comments() == model.review.comments())
  assert_true(failed.review.refresh_error.unwrap().contains("expired"))
  assert_true(failed.review.draft() == with_draft.review.draft())

  let (stale, _) = update_review(
    with_draft,
    CommentsLoaded(4, 0, Err(authentication_required_error())),
    emit,
  )
  assert_true(stale == with_draft)
}

///|
test "PR head race preserves the line draft and waits for manual snapshot loading" {
  let view = review_test_view()
  let anchor = canonical_anchor(
    parse_canonical_patch("src/main.mbt", view.files[0].file.patch),
    Right,
    2,
  ).unwrap()
  let model = Model::{
    viewed: empty_viewed_state(0),
    input: canonical_github_url(view.reference),
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    file_tree: initial_file_tree_state(),
    auth: SignedIn(
      user_id=Some("reviewer"),
      login=Some("reviewer"),
      install_url=None,
    ),
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: Some("reviewer"),
    review: review_fixture(
      initial_review_state(),
      refresh=RefreshIdle,
      snapshot_stale=false,
      deletion=None,
      deleted=[],
      comments=CommentsLoading,
      draft=Some({
        snapshot: None,
        id: { generation: 0, sequence: 0, },
        kind: InlineDraft(0, anchor),
        body: "keep this draft",
        submitting: true,
        error: None,
      }),
      stage=Some(CheckingHead),
      can_comment=SignedIn(
          user_id=Some("reviewer"),
          login=Some("reviewer"),
          install_url=None,
        )
        is SignedIn(..),
      login=match
        SignedIn(
          user_id=Some("reviewer"),
          login=Some("reviewer"),
          install_url=None,
        ) {
        SignedIn(login~, ..) => login
        _ => None
      },
    ),
  }
  let changed = ApiPull::{
    title: "Moved head",
    html_url: "https://github.com/upstream/project/pull/17",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "upstream/project", }),
    },
    head: {
      sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      repo: Some({ full_name: "upstream/project", }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (next, _) = update_review(
    model,
    CommentHeadChecked(5, model.review.submission_id, anchor, Ok(changed)),
    emit,
  )
  assert_eq(next.generation, 5)
  assert_true(next.phase == model.phase)
  assert_true(next.review.snapshot_stale)
  guard next.review.draft() is Some(draft) else {
    fail("expected the draft to survive the head refresh")
  }
  assert_eq(draft.body, "keep this draft")
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("PR updated"))

  let (stale, _) = update_review(
    next,
    CommentsLoaded(
      5,
      0,
      Ok({ issue_comments: [], review_comments: [], commit_comments: [], }),
    ),
    emit,
  )
  assert_true(stale == next)
}

///|
test "PR comment head authentication failure signs out and preserves the draft" {
  let view = review_test_view()
  let anchor = canonical_anchor(
    parse_canonical_patch("src/main.mbt", view.files[0].file.patch),
    Right,
    2,
  ).unwrap()
  let base = review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
  let original = CommentDraft::{
    snapshot: None,
    id: { generation: 0, sequence: 0, },
    kind: InlineDraft(0, anchor),
    body: "keep this line draft",
    submitting: true,
    error: None,
  }
  let model = with_review(
    base,
    review_state_with_draft(base.review, Some(original)),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let pending = with_review(
    model,
    review_fixture(model.review, stage=Some(CheckingHead)),
  )
  let (failed, _) = update_review(
    pending,
    CommentHeadChecked(
      5,
      pending.review.submission_id,
      anchor,
      Err(authentication_required_error()),
    ),
    emit,
  )
  guard failed.auth is AuthFailed(message) else {
    fail("expected the head check to invalidate authentication")
  }
  assert_true(message.contains("expired"))
  guard failed.review.draft() is Some(draft) else {
    fail("expected the line draft to survive the authentication failure")
  }
  assert_true(draft.kind == original.kind)
  assert_eq(draft.body, original.body)
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("expired"))
}

///|
test "comment completion inserts GitHub response and failures retain the draft" {
  let view = review_test_view()
  let draft = CommentDraft::{
    snapshot: None,
    id: { generation: 0, sequence: 0, },
    kind: OverallDraft,
    body: "new comment",
    submitting: true,
    error: None,
  }
  let model = Model::{
    viewed: empty_viewed_state(0),
    input: canonical_github_url(view.reference),
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    file_tree: initial_file_tree_state(),
    auth: SignedIn(
      user_id=Some("reviewer"),
      login=Some("reviewer"),
      install_url=None,
    ),
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: Some("reviewer"),
    review: review_fixture(
      initial_review_state(),
      refresh=RefreshIdle,
      snapshot_stale=false,
      deletion=None,
      deleted=[],
      comments=CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
      draft=Some(draft),
      stage=Some(PostingIssue),
      can_comment=SignedIn(
          user_id=Some("reviewer"),
          login=Some("reviewer"),
          install_url=None,
        )
        is SignedIn(..),
      login=match
        SignedIn(
          user_id=Some("reviewer"),
          login=Some("reviewer"),
          install_url=None,
        ) {
        SignedIn(login~, ..) => login
        _ => None
      },
    ),
  }
  let created = ApiIssueComment::{
    id: Int64::from_int(42),
    body: "new comment",
    html_url: "https://github.com/upstream/project/pull/17#issuecomment-42",
    created_at: "2026-08-18T08:00:00Z",
    user: Some({ login: "reviewer", }),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (posted, _) = update_review(
    model,
    IssueCommentCreated(5, model.review.submission_id, Ok(created)),
    emit,
  )
  assert_true(posted.review.draft() is None)
  guard posted.review.comments() is CommentsReady(bundle) else {
    fail("expected optimistic comments to stay visible")
  }
  assert_eq(bundle.issue_comments.map(comment => comment.id), [created.id])

  let (failed, _) = update_review(
    model,
    IssueCommentCreated(
      5,
      model.review.submission_id,
      Err(
        HttpRequestError::HttpRequestError(
          status=422,
          code="invalid_comment_anchor",
          detail="Validation Failed",
        ),
      ),
    ),
    emit,
  )
  guard failed.review.draft() is Some(retained) else {
    fail("expected failed submission to retain the draft")
  }
  assert_eq(retained.body, "new comment")
  assert_false(retained.submitting)
  assert_true(retained.error.unwrap().contains("anchor"))
  assert_true(
    failed.auth
    is SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), ..),
  )
}

///|
test "comment creation authentication failures sign out and retain the draft" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for
    stage in [
      @comments.PostingIssue,
      PostingReview,
      PostingCommit,
      PostingReply,
    ] {
    let base = review_reply_test_model()
    let view = review_test_view()
    let anchor = ReviewAnchor::{
      path: "src/main.mbt",
      side: Right,
      line: 2,
      position: Some(3),
    }
    let kind : @comments.DraftKind = match stage {
      PostingIssue => OverallDraft
      PostingReply => ReplyDraft(20L)
      _ => InlineDraft(0, anchor)
    }
    let review = review_fixture(
      base.review,
      draft=Some({
        snapshot: None,
        id: { generation: 5, sequence: 1, },
        kind,
        body: "keep this comment",
        submitting: false,
        error: None,
      }),
      stage=Some(stage),
    )
    let model = if stage is PostingCommit {
      let commit = {
        ..view,
        reference: @github.commit_reference("upstream", "project", view.sha),
      }
      { ..base, review, route: Some(commit.reference), phase: Showing(commit), }
    } else {
      with_review(base, review)
    }
    let id = model.review.submission_id
    let message : ReviewMsg = match stage {
      PostingIssue =>
        IssueCommentCreated(5, id, Err(authentication_required_error()))
      PostingReview =>
        ReviewCommentCreated(5, id, Err(authentication_required_error()))
      PostingCommit =>
        CommitCommentCreated(5, id, Err(authentication_required_error()))
      _ => ReviewReplyCreated(5, id, Err(authentication_required_error()))
    }
    let (failed, _) = update_review(model, message, emit)
    guard failed.auth is AuthFailed(message) else {
      fail("expected auth failure")
    }
    assert_true(message.contains("expired"))
    assert_false(review_can_comment(failed.review))
    let draft = failed.review.draft().unwrap()
    assert_true(draft.kind == kind)
    assert_eq(draft.body, "keep this comment")
    assert_false(draft.submitting)
    assert_true(draft.error.unwrap().contains("expired"))
    ignore(view)
  }
}

///|
fn signed_in_api_status(login : String) -> ApiAuthStatus {
  {
    device_flow: None,
    csrf_token: "csrf-test",
    authenticated: true,
    login: Some(login),
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    user_id: Some(login),
  }
}

///|
fn anonymous_api_status() -> ApiAuthStatus {
  {
    device_flow: None,
    csrf_token: "csrf-test",
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    user_id: None,
  }
}

///|
fn signed_in_api_status_without_login() -> ApiAuthStatus {
  {
    device_flow: None,
    csrf_token: "csrf-test",
    authenticated: true,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    user_id: None,
  }
}

///|
fn auth_test_model(
  auth : AuthStatus,
  phase : Phase,
  route : CommitRef?,
  last_authenticated_user_id? : String? = None,
) -> Model {
  {
    viewed: empty_viewed_state(0),
    input: "",
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase,
    route,
    file_tree: initial_file_tree_state(),
    auth,
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id,
    review: review_fixture(
      initial_review_state(),
      deletion=None,
      deleted=[],
      comments=CommentsFailed("private repository"),
      draft=None,
      stage=initial_review_state().submission(),
      can_comment=auth is SignedIn(..),
      login=match auth {
        SignedIn(login~, ..) => login
        _ => None
      },
    ),
  }
}

///|
fn auth_identity_test_model(auth : AuthStatus, login : String?) -> Model {
  let model = review_test_model(auth)
  {
    ..model,
    file_tree: {
      ..model.file_tree,
      drawer_open: true,
      search_open: true,
      search_query: "main",
      selected_file_index: Some(0),
    },
    auth,
    auth_revision: 0,
    restore_pending: false,
    last_authenticated_user_id: login,
    review: review_fixture(
      initial_review_state(),
      deletion=None,
      deleted=[],
      comments=model.review.comments(),
      draft=Some({
        snapshot: None,
        id: { generation: 0, sequence: 0, },
        kind: OverallDraft,
        body: "account-owned draft",
        submitting: false,
        error: None,
      }),
      stage=initial_review_state().submission(),
      can_comment=auth is SignedIn(..),
      login=match auth {
        SignedIn(login~, ..) => login
        _ => None
      },
    ),
  }
}

///|
test "account changes and confirmed anonymity clear review state and reload" {
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let alice = auth_identity_test_model(
    SignedIn(user_id=Some("alice"), login=Some("alice"), install_url=None),
    Some("alice"),
  )
  let old_generation = alice.generation
  let (bob, _) = update_auth(
    alice,
    ReactivationAuthStatusLoaded(
      0,
      old_generation,
      Some(view.reference),
      Ok(signed_in_api_status("bob")),
    ),
    emit,
  )
  assert_eq(bob.generation, old_generation + 1)
  assert_true(bob.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(bob.auth is SignedIn(user_id=Some("bob"), login=Some("bob"), ..))
  assert_eq(bob.last_authenticated_user_id, Some("bob"))
  assert_true(bob.review.comments() is CommentsLoading)
  assert_true(bob.review.draft() is None)
  assert_true(bob.file_tree == reset_file_tree_state(alice.file_tree))

  let (anonymous, _) = update_auth(
    alice,
    ReactivationAuthStatusLoaded(
      0,
      old_generation,
      Some(view.reference),
      Ok(anonymous_api_status()),
    ),
    emit,
  )
  assert_eq(anonymous.generation, old_generation + 1)
  assert_true(anonymous.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(anonymous.auth is Anonymous(_))
  assert_true(anonymous.last_authenticated_user_id is None)
  assert_true(anonymous.review.comments() is CommentsLoading)
  assert_true(anonymous.review.draft() is None)
  assert_true(anonymous.file_tree == reset_file_tree_state(alice.file_tree))
}

///|
test "installation URL changes do not cross the signed-in account boundary" {
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let alice = auth_identity_test_model(
    SignedIn(
      user_id=Some("alice"),
      login=Some("alice"),
      install_url=Some("https://github.com/apps/moondiff-old/installations/new"),
    ),
    Some("alice"),
  )
  let old_generation = alice.generation
  let (updated, _) = update_auth(
    alice,
    ReactivationAuthStatusLoaded(
      0,
      old_generation,
      Some(view.reference),
      Ok({
        device_flow: None,
        csrf_token: "csrf-test",
        authenticated: true,
        login: Some("alice"),
        install_url: Some(
          "https://github.com/apps/moondiff-new/installations/new",
        ),
        user_id: Some("alice"),
      }),
    ),
    emit,
  )
  assert_eq(updated.generation, old_generation)
  assert_true(updated.phase == alice.phase)
  guard updated.auth is SignedIn(login~, install_url~, ..) else {
    fail("expected Alice to remain signed in")
  }
  assert_eq(login, Some("alice"))
  assert_eq(
    install_url,
    Some("https://github.com/apps/moondiff-new/installations/new"),
  )
  assert_eq(updated.last_authenticated_user_id, Some("alice"))
  assert_true(updated.review.draft() == alice.review.draft())
  assert_true(updated.file_tree == alice.file_tree)
}

///|
test "account boundary generation ignores old diff comment and submission responses" {
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let alice = auth_identity_test_model(
    SignedIn(user_id=Some("alice"), login=Some("alice"), install_url=None),
    Some("alice"),
  )
  let old_generation = alice.generation
  let (bob, _) = update_auth(
    alice,
    ReactivationAuthStatusLoaded(
      0,
      old_generation,
      Some(view.reference),
      Ok(signed_in_api_status("bob")),
    ),
    emit,
  )
  let (after_diff, _) = update_load(
    bob,
    PullMetadataLoaded(
      old_generation,
      0,
      Err(GitHubRequestError::GitHubRequestError("late Alice diff")),
    ),
    emit,
  )
  assert_true(after_diff == bob)
  let (after_comments, _) = update_review(
    bob,
    CommentsLoaded(
      old_generation,
      0,
      Ok({ issue_comments: [], review_comments: [], commit_comments: [], }),
    ),
    emit,
  )
  assert_true(after_comments == bob)
  let bob_with_comments = with_review(
    bob,
    review_state_with_comments(
      bob.review,
      CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
    ),
  )
  let late_comment = ApiIssueComment::{
    id: Int64::from_int(42),
    body: "late Alice comment",
    html_url: "https://github.com/upstream/project/issues/17#issuecomment-42",
    created_at: "2026-09-03T08:00:00Z",
    user: Some({ login: "alice", }),
  }
  let (after_submission, _) = update_review(
    bob_with_comments,
    IssueCommentCreated(old_generation, 0, Ok(late_comment)),
    emit,
  )
  assert_true(after_submission == bob_with_comments)
}

///|
test "an authenticated result without a login cannot reuse known account state" {
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let alice = auth_identity_test_model(
    AuthFailed("Your GitHub session expired."),
    Some("alice"),
  )
  let (unverified, _) = update_auth(
    alice,
    ReactivationAuthStatusLoaded(
      0,
      alice.generation,
      Some(view.reference),
      Ok(signed_in_api_status_without_login()),
    ),
    emit,
  )
  assert_eq(unverified.generation, alice.generation + 1)
  assert_true(unverified.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(unverified.auth is SignedIn(user_id=None, login=None, ..))
  assert_true(unverified.last_authenticated_user_id is None)
  assert_true(unverified.review.draft() is None)
}

///|
test "successful local logout clears account state and reloads" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let alice = auth_identity_test_model(
    SignedIn(user_id=Some("alice"), login=Some("alice"), install_url=None),
    Some("alice"),
  )
  let checking = with_auth(alice, AuthChecking)
  assert_true(checking.auth is AuthChecking)
  assert_eq(checking.last_authenticated_user_id, Some("alice"))
  assert_true(checking.review.draft() == alice.review.draft())
  let (logged_out, _) = update_auth(
    checking,
    AuthLogoutFinished(0, Ok(anonymous_api_status())),
    emit,
  )
  assert_eq(logged_out.generation, alice.generation + 1)
  assert_true(logged_out.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(logged_out.auth is Anonymous(_))
  assert_true(logged_out.last_authenticated_user_id is None)
  assert_true(logged_out.review.comments() is CommentsLoading)
  assert_true(logged_out.review.draft() is None)
}

///|
test "reactivation synchronizes login and logout before refreshing comments" {
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let anonymous = review_test_model(Anonymous(None))
  let (signed_in, _) = update_auth(
    anonymous,
    ReactivationAuthStatusLoaded(
      0,
      anonymous.generation,
      Some(view.reference),
      Ok(signed_in_api_status("cross-tab-user")),
    ),
    emit,
  )
  assert_true(
    signed_in.auth
    is SignedIn(
      user_id=Some("cross-tab-user"),
      login=Some("cross-tab-user"),
      ..
    ),
  )
  assert_true(signed_in.review.comments() is CommentsReady(_))

  let ready = with_review(
    signed_in,
    review_state_with_comments(
      signed_in.review,
      CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
    ),
  )
  let (signed_out, _) = update_auth(
    ready,
    ReactivationAuthStatusLoaded(
      0,
      ready.generation,
      Some(view.reference),
      Ok(anonymous_api_status()),
    ),
    emit,
  )
  assert_true(signed_out.auth is Anonymous(_))
  assert_true(signed_out.review.comments() is CommentsLoading)
}

///|
test "reactivation login retries a private repository load" {
  let reference = pull_reference("upstream", "private-project", "17")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = auth_test_model(
    Anonymous(None),
    LoadFailed("private repository"),
    Some(reference),
  )
  let (retried, _) = update_auth(
    model,
    ReactivationAuthStatusLoaded(
      0,
      model.generation,
      Some(reference),
      Ok(signed_in_api_status("cross-tab-user")),
    ),
    emit,
  )
  assert_eq(retried.generation, model.generation + 1)
  assert_true(retried.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(
    retried.auth
    is SignedIn(
      user_id=Some("cross-tab-user"),
      login=Some("cross-tab-user"),
      ..
    ),
  )
}

///|
test "reactivation login restarts an anonymous load and ignores its late failure" {
  let reference = pull_reference("upstream", "private-project", "17")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = auth_test_model(
    Anonymous(None),
    LoadingPullMetadata(reference~, attempt=0),
    Some(reference),
  )
  let old_generation = model.generation
  let (restarted, _) = update_auth(
    model,
    ReactivationAuthStatusLoaded(
      0,
      old_generation,
      Some(reference),
      Ok(signed_in_api_status("cross-tab-user")),
    ),
    emit,
  )
  assert_eq(restarted.generation, old_generation + 1)
  assert_true(restarted.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(
    restarted.auth
    is SignedIn(
      user_id=Some("cross-tab-user"),
      login=Some("cross-tab-user"),
      ..
    ),
  )

  let (after_late_failure, _) = update_load(
    restarted,
    PullMetadataLoaded(
      old_generation,
      0,
      Err(GitHubRequestError::GitHubRequestError("late anonymous 404")),
    ),
    emit,
  )
  assert_true(after_late_failure == restarted)
}

///|
test "web sign-in retries a private repository load" {
  let reference = pull_reference("upstream", "private-project", "17")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = auth_test_model(
    Authorizing(starting_device("test-attempt-00000000"), ""),
    LoadFailed("private repository"),
    Some(reference),
  )
  let (retried, _) = update_auth(
    model,
    DeviceUpdated(
      0,
      "test-attempt-00000000",
      true,
      Ok({
        request_id: "test-attempt-00000000",
        status: { ..signed_in_api_status("reviewer"), },
      }),
    ),
    emit,
  )
  assert_eq(retried.generation, 6)
  assert_true(retried.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(
    retried.auth
    is SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), ..),
  )
}

///|
test "web sign-in restarts an anonymous load and ignores its late failure" {
  let reference = pull_reference("upstream", "private-project", "17")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = auth_test_model(
    Authorizing(starting_device("test-attempt-00000000"), ""),
    LoadingPullMetadata(reference~, attempt=0),
    Some(reference),
  )
  let old_generation = model.generation
  let (restarted, _) = update_auth(
    model,
    DeviceUpdated(
      0,
      "test-attempt-00000000",
      true,
      Ok({
        request_id: "test-attempt-00000000",
        status: { ..signed_in_api_status("reviewer"), },
      }),
    ),
    emit,
  )
  assert_eq(restarted.generation, old_generation + 1)
  assert_true(restarted.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(
    restarted.auth
    is SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), ..),
  )

  let (after_late_failure, _) = update_load(
    restarted,
    PullMetadataLoaded(
      old_generation,
      0,
      Err(GitHubRequestError::GitHubRequestError("late anonymous 404")),
    ),
    emit,
  )
  assert_true(after_late_failure == restarted)
}

///|
test "top-level reducer routes every message domain" {
  let model = initial_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)

  let auth_msg : AuthMsg = AuthStatusLoaded(0, Ok(anonymous_api_status()))
  let (auth_routed, _) = update(model, Auth(auth_msg), emit)
  let (auth_direct, _) = update_auth(model, auth_msg, emit)
  assert_true(auth_routed == auth_direct)

  let review_msg : ReviewMsg = PageReactivated
  let (review_routed, _) = update(model, Review(review_msg), emit)
  let (review_direct, _) = update_review(model, review_msg, emit)
  assert_true(review_routed == review_direct)

  let load_msg : LoadMsg = PullMetadataLoaded(
    model.generation + 1,
    0,
    Err(GitHubRequestError::GitHubRequestError("ignored stale response")),
  )
  let (load_routed, _) = update(model, Load(load_msg), emit)
  let (load_direct, _) = update_load(model, load_msg, emit)
  assert_true(load_routed == load_direct)

  let ui_msg : UiMsg = InputChanged(
    "https://github.com/example/repo/commit/abcdef1",
  )
  let (ui_routed, _) = update(model, Ui(ui_msg), emit)
  let (ui_direct, _) = update_ui(model, ui_msg, emit)
  assert_true(ui_routed == ui_direct)
}

///|
test "deletion requires ownership and confirmation, preserves failures, and rejects stale results" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let initial = review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
  let comment : ApiIssueComment = {
    id: 100L,
    body: "owned",
    html_url: "https://github.com/comment/100",
    created_at: "2026-09-07",
    user: Some({ login: "reviewer", }),
  }
  let bundle : ApiCommentBundle = {
    issue_comments: [comment],
    review_comments: [],
    commit_comments: [],
  }
  let model = with_review(
    initial,
    review_fixture(initial.review, comments=CommentsReady(bundle)),
  )
  let id = @comments.IssueComment(100L)
  let (unconfirmed, _) = update_review(model, ConfirmCommentDelete(id), emit)
  assert_true(unconfirmed.review == model.review)
  let other = with_auth(
    model,
    SignedIn(
      user_id=Some("someone-else"),
      login=Some("someone-else"),
      install_url=None,
    ),
  )
  let (denied, _) = update_review(other, AskDelete(id), emit)
  assert_true(denied.review.deletion is None)
  let (confirming, _) = update_review(model, AskDelete(id), emit)
  assert_true(confirming.review.deletion == Some(ConfirmDelete(id)))
  let (cancelled, _) = update_review(confirming, CancelDelete, emit)
  assert_true(cancelled.review.deletion is None)
  let (pending, _) = update_review(confirming, ConfirmCommentDelete(id), emit)
  assert_true(pending.review.deletion == Some(Deleting(id)))
  let (duplicate, _) = update_review(pending, ConfirmCommentDelete(id), emit)
  assert_true(duplicate.review == pending.review)
  let (failed, _) = update_review(
    pending,
    CommentDeleted(
      model.generation,
      1,
      id,
      Err(authentication_required_error()),
    ),
    emit,
  )
  assert_true(failed.review.deletion is Some(DeleteFailed(_, _)))
  assert_true(failed.review.comments() == CommentsReady(bundle))
  assert_true(failed.auth is AuthFailed(_))
  let signed_in = with_auth(failed, model.auth)
  let (retrying, _) = update_review(signed_in, ConfirmCommentDelete(id), emit)
  let (deleted, _) = update_review(
    retrying,
    CommentDeleted(
      model.generation,
      retrying.review.deletion_id,
      id,
      Ok({ deleted: true, }),
    ),
    emit,
  )
  guard deleted.review.comments() is CommentsReady(empty) else {
    fail("expected comments")
  }
  assert_true(empty.issue_comments.is_empty())
  let (stale_refresh, _) = review_test_refresh(deleted, bundle, emit)
  assert_true(stale_refresh.review.comments() == deleted.review.comments())
  let navigated = {
    ..pending,
    generation: pending.generation + 1,
    review: initial.review,
  }
  let (stale_delete, _) = update_review(
    navigated,
    CommentDeleted(
      model.generation,
      retrying.review.deletion_id,
      id,
      Ok({ deleted: true, }),
    ),
    emit,
  )
  assert_true(stale_delete.review == navigated.review)
  let (changed_review, _) = review_state_with_auth_identity(
    pending,
    SignedIn(
      user_id=Some("new-account"),
      login=Some("new-account"),
      install_url=None,
    ),
  )
  let (changed, _) = reload_after_auth_identity_boundary(changed_review, emit)
  let (old_account_delete, _) = update_review(
    changed,
    CommentDeleted(
      model.generation,
      retrying.review.deletion_id,
      id,
      Ok({ deleted: true, }),
    ),
    emit,
  )
  assert_true(old_account_delete.review == changed.review)
}

///|
fn review_reply_test_model() -> Model {
  let model = review_test_model(
    SignedIn(user_id=Some("reviewer"), login=Some("reviewer"), install_url=None),
  )
  let root : ApiReviewComment = {
    id: 20L,
    body: "root",
    html_url: "",
    created_at: "",
    user: Some({ login: "reviewer", }),
    path: "src/main.mbt",
    line: Some(2),
    original_line: Some(2),
    side: Some(@protocol.CommentSide::Right),
    position: Some(3),
    commit_id: "head",
    in_reply_to_id: None,
  }
  with_review(
    model,
    review_fixture(
      model.review,
      comments=CommentsReady({
        issue_comments: [],
        review_comments: [root, { ..root, id: 21L, in_reply_to_id: Some(20L), }],
        commit_comments: [],
      }),
    ),
  )
}

///|
test "reply targets and drafts guard deletion in every ordering" {
  let model = review_reply_test_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let id = @comments.ReviewComment(20L)
  assert_true(@comments.valid_reply_target(model.review, 20L))
  for target in [21L, 99L] {
    assert_false(@comments.valid_reply_target(model.review, target))
    let (blocked, _) = update_review(model, OpenReplyDraft(target), emit)
    assert_true(blocked == model)
  }
  let (confirming, _) = update_review(model, AskDelete(id), emit)
  let (drafting, _) = update_review(confirming, OpenReplyDraft(20L), emit)
  for submitting in [false, true] {
    for body in ["", "preserve me"] {
      let guarded = with_review(
        drafting,
        review_fixture(
          drafting.review,
          draft=Some({
            snapshot: None,
            id: { generation: 0, sequence: 0, },
            kind: ReplyDraft(20L),
            body,
            submitting,
            error: None,
          }),
          stage=drafting.review.submission(),
        ),
      )
      assert_true(@comments.draft_blocks_deletion(guarded.review, id))
      assert_false(
        @comments.draft_blocks_deletion(
          guarded.review,
          @comments.ReviewComment(21L),
        ),
      )
      for
        deletion in [
          None,
          Some(@comments.ConfirmDelete(id)),
          Some(@comments.DeleteFailed(id, "retry")),
        ] {
        let guarded = with_review(
          guarded,
          review_fixture(guarded.review, deletion~),
        )
        for msg in [AskDelete(id), ConfirmCommentDelete(id)] {
          let (blocked, _) = update_review(guarded, msg, emit)
          assert_true(blocked == guarded)
        }
      }
    }
  }
  let (cancelled, _) = update_review(drafting, CancelDraft, emit)
  let (deleting, _) = update_review(cancelled, ConfirmCommentDelete(id), emit)
  assert_true(deleting.review.deletion == Some(Deleting(id)))
  let (blocked, _) = update_review(deleting, OpenReplyDraft(20L), emit)
  assert_true(blocked == deleting)
  let (drafting, _) = update_review(model, OpenReplyDraft(20L), emit)
  let (drafting, _) = update_review(
    drafting,
    DraftBodyChanged("preserve me"),
    emit,
  )
  let (submitted, _) = update_review(drafting, SubmitDraft, emit)
  assert_true(submitted.review.draft().unwrap().submitting)
  guard drafting.review.comments() is CommentsReady(current) else {
    fail("comments")
  }
  let missing = {
    ..current,
    review_comments: current.review_comments.filter(c => c.id != 20L),
  }
  let (invalid, _) = review_test_refresh(drafting, missing, emit)
  let (blocked, _) = update_review(invalid, SubmitDraft, emit)
  assert_false(blocked.review.draft().unwrap().submitting)
  assert_eq(blocked.review.draft().unwrap().body, "preserve me")
  assert_true(blocked.review.draft().unwrap().error is Some(_))
  for target in [21L, 99L] {
    let (cancelled, _) = update_review(invalid, CancelDraft, emit)
    let (rejected, _) = update_review(cancelled, OpenReplyDraft(target), emit)
    assert_true(rejected.review.draft() is None)
  }
  let empty : ApiCommentBundle = {
    issue_comments: [],
    review_comments: [],
    commit_comments: [],
  }
  let (removed, _) = review_test_refresh(drafting, empty, emit)
  assert_true(removed.review.draft() == drafting.review.draft())
  let (blocked, _) = update_review(removed, SubmitDraft, emit)
  assert_false(blocked.review.draft().unwrap().submitting)
  let (deletion_blocked, _) = update_review(
    drafting,
    ConfirmCommentDelete(id),
    emit,
  )
  assert_true(deletion_blocked == drafting)
  let (pending_removed, _) = review_test_refresh(submitted, empty, emit)
  assert_true(pending_removed.review.draft().unwrap().submitting)
  guard model.review.comments() is CommentsReady(bundle) else {
    fail("expected comments")
  }
  let reply = { ..bundle.review_comments[1], body: "preserve me", }
  let (finished, _) = update_review(
    pending_removed,
    ReviewReplyCreated(
      model.generation,
      submitted.review.submission_id,
      Ok(reply),
    ),
    emit,
  )
  assert_true(finished.review.draft() is None)
}
