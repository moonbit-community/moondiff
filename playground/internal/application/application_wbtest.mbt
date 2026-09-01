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
    input: "https://github.com/a/b/commit/abcdef1",
    generation: 2,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Idle,
    route: None,
    share_url: None,
    copy_status: CopyReady,
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
    input: canonical_github_url(reference),
    generation,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase,
    route: Some(reference),
    share_url: None,
    copy_status: CopyReady,
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
    input: "",
    generation: 9,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
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
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: DiffCache::empty(),
  }
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
  assert_false(model.ignore_comments)
  assert_false(model.ignore_tests)
  let reference = commit_reference("owner", "repo", "abcdef1")
  assert_eq(playground_route(reference), "#/owner/repo/commit/abcdef1")
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
  guard filtered is MoonBit(document=Whole(fragment), status=IgnoredOnly) else {
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
test "extension request errors retain diagnostics and format unknown codes neutrally" {
  let error : Error = ExtensionRequestError::ExtensionRequestError(
    status=400,
    code="invalid_arguments",
    detail="Missing RPC argument: sha",
  )
  guard error
    is ExtensionRequestError::ExtensionRequestError(status~, code~, detail~) else {
    fail("expected a structured extension error")
  }
  assert_eq(status, 400)
  assert_eq(code, "invalid_arguments")
  assert_eq(detail, "Missing RPC argument: sha")
  assert_eq(
    error_message(error, true),
    "Moondiff extension request failed (status 400, invalid_arguments): Missing RPC argument: sha",
  )
}

///|
test "extension request codes retain actionable GitHub guidance" {
  assert_eq(
    comment_failure_message(
      ExtensionRequestError::ExtensionRequestError(
        status=403,
        code="rate_limit",
        detail="API rate limit exceeded",
      ),
    ),
    "GitHub API rate limit exceeded. Sign in or try again after the reset time.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError::ExtensionRequestError(
        status=401,
        code="authentication_required",
        detail="Bad credentials",
      ),
    ),
    "Your GitHub session expired. Sign in again, then retry.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError::ExtensionRequestError(
        status=404,
        code="not_found_or_not_installed",
        detail="Not Found",
      ),
    ),
    "GitHub could not access this repository. Sign in and install the GitHub App for private repositories.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError::ExtensionRequestError(
        status=403,
        code="permission_denied",
        detail="Resource not accessible by integration",
      ),
    ),
    "GitHub denied this action. Install the app for this repository and check its Pull requests permission.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError::ExtensionRequestError(
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
    "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later.",
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
  view
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
    review: {
      auth,
      comments: CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
      draft: None,
    },
  }
}

///|
fn authentication_required_error() -> Error {
  ExtensionRequestError::ExtensionRequestError(
    status=401,
    code="authentication_required",
    detail="Bad credentials",
  )
}

///|
fn review_test_device_authorization() -> DeviceAuthorization {
  {
    flow_id: "flow-1",
    user_code: "ABCD-EFGH",
    verification_uri: "https://github.com/login/device",
    expires_in: 900,
    poll_after: 1,
    install_url: None,
    copy_status: DeviceCodeCopyReady,
  }
}

///|
test "only signed-in reviews can open comment drafts" {
  let view = review_test_view()
  let anchor = canonical_anchor(
    parse_canonical_patch("src/main.mbt", view.files[0].file.patch),
    Right,
    2,
  ).unwrap()
  let device = review_test_device_authorization()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let auths : Array[AuthStatus] = [
    WebReadOnly,
    AuthChecking,
    Anonymous(None),
    DeviceAuthorizing(device),
    DeviceCancelling(device),
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

  let signed_in = review_test_model(SignedIn(Some("reviewer")))
  assert_true(review_can_comment(signed_in.review))
  let (overall, _) = update_review(signed_in, OpenOverallDraft, emit)
  guard overall.review.draft is Some(overall_draft) else {
    fail("expected an overall draft")
  }
  assert_true(overall_draft.kind is OverallDraft)
  let (inline, _) = update_review(signed_in, OpenInlineDraft(0, anchor), emit)
  guard inline.review.draft is Some(inline_draft) else {
    fail("expected an inline draft")
  }
  assert_true(
    inline_draft.kind is InlineDraft(0, selected) && selected == anchor,
  )
  let comment_id = Int64::from_int(20)
  let (reply, _) = update_review(signed_in, OpenReplyDraft(comment_id), emit)
  guard reply.review.draft is Some(reply_draft) else {
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
        kind: OverallDraft,
        body: "comment body",
        submitting: false,
        error: None,
      }),
    ),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (blocked, _) = update_review(with_draft, SubmitDraft, emit)
  guard blocked.review.draft is Some(draft) else {
    fail("expected the blocked draft to be retained")
  }
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("Sign in with GitHub"))
}

///|
test "comment loading authentication failure signs out and preserves the draft" {
  let model = review_test_model(SignedIn(Some("reviewer")))
  let draft = CommentDraft::{
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
    with_draft,
    CommentsLoaded(5, Err(authentication_required_error())),
    emit,
  )
  guard failed.review.auth is AuthFailed(auth_message) else {
    fail("expected comment loading to invalidate authentication")
  }
  assert_true(auth_message.contains("expired"))
  assert_false(review_can_comment(failed.review))
  guard failed.review.comments is CommentsFailed(comments_message) else {
    fail("expected comment loading to retain its failure")
  }
  assert_true(comments_message.contains("expired"))
  assert_true(failed.review.draft == Some(draft))

  let (stale, _) = update_review(
    with_draft,
    CommentsLoaded(4, Err(authentication_required_error())),
    emit,
  )
  assert_true(stale == with_draft)
}

///|
test "PR head race preserves the line draft and starts a fresh snapshot" {
  let view = review_test_view()
  let anchor = canonical_anchor(
    parse_canonical_patch("src/main.mbt", view.files[0].file.patch),
    Right,
    2,
  ).unwrap()
  let model = Model::{
    input: canonical_github_url(view.reference),
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
    review: {
      auth: SignedIn(Some("reviewer")),
      comments: CommentsLoading,
      draft: Some({
        kind: InlineDraft(0, anchor),
        body: "keep this draft",
        submitting: true,
        error: None,
      }),
    },
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
    CommentHeadChecked(5, anchor, Ok(changed)),
    emit,
  )
  assert_eq(next.generation, 6)
  assert_true(next.phase is LoadingPullMetadata(attempt=0, ..))
  guard next.review.draft is Some(draft) else {
    fail("expected the draft to survive the head refresh")
  }
  assert_eq(draft.body, "keep this draft")
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("head changed"))

  let (stale, _) = update_review(
    next,
    CommentsLoaded(
      5,
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
  let base = review_test_model(SignedIn(Some("reviewer")))
  let original = CommentDraft::{
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
  let (failed, _) = update_review(
    model,
    CommentHeadChecked(5, anchor, Err(authentication_required_error())),
    emit,
  )
  guard failed.review.auth is AuthFailed(message) else {
    fail("expected the head check to invalidate authentication")
  }
  assert_true(message.contains("expired"))
  guard failed.review.draft is Some(draft) else {
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
    kind: OverallDraft,
    body: "new comment",
    submitting: true,
    error: None,
  }
  let model = Model::{
    input: canonical_github_url(view.reference),
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
    review: {
      auth: SignedIn(Some("reviewer")),
      comments: CommentsReady({
        issue_comments: [],
        review_comments: [],
        commit_comments: [],
      }),
      draft: Some(draft),
    },
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
    IssueCommentCreated(5, Ok(created)),
    emit,
  )
  assert_true(posted.review.draft is None)
  guard posted.review.comments is CommentsReady(bundle) else {
    fail("expected optimistic comments to stay visible")
  }
  assert_eq(bundle.issue_comments.map(comment => comment.id), [created.id])

  let (failed, _) = update_review(
    model,
    IssueCommentCreated(
      5,
      Err(
        ExtensionRequestError::ExtensionRequestError(
          status=422,
          code="invalid_comment_anchor",
          detail="Validation Failed",
        ),
      ),
    ),
    emit,
  )
  guard failed.review.draft is Some(retained) else {
    fail("expected failed submission to retain the draft")
  }
  assert_eq(retained.body, "new comment")
  assert_false(retained.submitting)
  assert_true(retained.error.unwrap().contains("anchor"))
  assert_true(failed.review.auth is SignedIn(Some("reviewer")))
}

///|
test "comment creation authentication failures sign out and retain the draft" {
  let base = review_test_model(SignedIn(Some("reviewer")))
  let original = CommentDraft::{
    kind: OverallDraft,
    body: "keep this comment",
    submitting: true,
    error: None,
  }
  let model = with_review(
    base,
    review_state_with_draft(base.review, Some(original)),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let messages : Array[ReviewMsg] = [
    IssueCommentCreated(5, Err(authentication_required_error())),
    ReviewCommentCreated(5, Err(authentication_required_error())),
    CommitCommentCreated(5, Err(authentication_required_error())),
    ReviewReplyCreated(5, Err(authentication_required_error())),
  ]
  for msg in messages {
    let (failed, _) = update_review(model, msg, emit)
    guard failed.review.auth is AuthFailed(message) else {
      fail("expected comment creation to invalidate authentication")
    }
    assert_true(message.contains("expired"))
    assert_false(review_can_comment(failed.review))
    guard failed.review.draft is Some(draft) else {
      fail("expected the comment draft to survive authentication failure")
    }
    assert_true(draft.kind == original.kind)
    assert_eq(draft.body, original.body)
    assert_false(draft.submitting)
    assert_true(draft.error.unwrap().contains("expired"))
  }
}

///|
fn device_api_status(
  flow_id : String,
  user_code? : String = "ABCD-EFGH",
  expires_in? : Int = 900,
  poll_after? : Int = 5,
) -> ApiAuthStatus {
  {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: Some({
      flow_id,
      user_code,
      verification_uri: "https://github.com/login/device",
      expires_in,
      poll_after,
    }),
  }
}

///|
fn signed_in_api_status(login : String) -> ApiAuthStatus {
  {
    authenticated: true,
    login: Some(login),
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: None,
  }
}

///|
fn anonymous_api_status() -> ApiAuthStatus {
  {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff-test/installations/new"),
    device_flow: None,
  }
}

///|
fn device_auth_test_model(
  auth : AuthStatus,
  phase : Phase,
  route : CommitRef?,
) -> Model {
  {
    input: "",
    generation: 5,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase,
    route,
    share_url: None,
    copy_status: CopyReady,
    review: {
      auth,
      comments: CommentsFailed("private repository"),
      draft: None,
    },
  }
}

///|
test "device authorization moves from code through pending to signed in" {
  let flow_id = "flow-current"
  let view = review_test_view()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let anonymous = device_auth_test_model(
    Anonymous(Some("https://github.com/apps/moondiff-test/installations/new")),
    Showing(view),
    Some(view.reference),
  )
  let (started, _) = update_auth(
    anonymous,
    DeviceAuthorizationStarted(Ok(device_api_status(flow_id))),
    emit,
  )
  guard started.review.auth is DeviceAuthorizing(device) else {
    fail("expected the device code to be displayed")
  }
  assert_eq(device.flow_id, flow_id)
  assert_eq(device.user_code, "ABCD-EFGH")
  assert_true(device.copy_status is DeviceCodeCopyReady)

  let (pending, _) = update_auth(
    started,
    DeviceAuthorizationPolled(
      flow_id,
      Ok(device_api_status(flow_id, expires_in=895, poll_after=7)),
    ),
    emit,
  )
  guard pending.review.auth is DeviceAuthorizing(waiting) else {
    fail("expected authorization to remain pending")
  }
  assert_eq(waiting.expires_in, 895)
  assert_eq(waiting.poll_after, 7)

  let (signed_in, _) = update_auth(
    pending,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("octocat"))),
    emit,
  )
  assert_true(signed_in.review.auth is SignedIn(Some("octocat")))
  assert_true(signed_in.review.comments is CommentsLoading)
}

///|
test "device code copy feedback and cancellation stay scoped to the current flow" {
  let flow_id = "flow-copy"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(flow_id)),
    Idle,
    None,
  )
  let (copying, _) = update_auth(model, CopyDeviceCode, emit)
  assert_true(copying == model)
  let (copied, _) = update_auth(model, DeviceCodeCopied(flow_id), emit)
  guard copied.review.auth is DeviceAuthorizing(done) else {
    fail("expected a device authorization")
  }
  assert_true(done.copy_status is DeviceCodeCopyDone)

  let (stale_copy, _) = update_auth(
    copied,
    DeviceCodeCopyFailed("old-flow", "no"),
    emit,
  )
  assert_true(stale_copy == copied)
  let (failed_copy, _) = update_auth(
    copied,
    DeviceCodeCopyFailed(flow_id, "clipboard denied"),
    emit,
  )
  guard failed_copy.review.auth is DeviceAuthorizing(failed) else {
    fail("expected a device authorization")
  }
  assert_true(failed.copy_status is DeviceCodeCopyError("clipboard denied"))

  let cancelling = with_review(
    failed_copy,
    review_state_with_auth(failed_copy.review, DeviceCancelling(failed)),
  )
  let (late_poll, _) = update_auth(
    cancelling,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("too-late"))),
    emit,
  )
  assert_true(late_poll == cancelling)
  let (cancelled, _) = update_auth(
    cancelling,
    DeviceAuthorizationCancelled(flow_id, Ok(anonymous_api_status())),
    emit,
  )
  assert_true(cancelled.review.auth is Anonymous(_))
}

///|
test "expired and stale device responses cannot authenticate another flow" {
  let current = "flow-new"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(current)),
    Idle,
    None,
  )
  let (stale_poll, _) = update_auth(
    model,
    DeviceAuthorizationPolled(
      "flow-old",
      Ok(signed_in_api_status("wrong-user")),
    ),
    emit,
  )
  assert_true(stale_poll == model)
  let (stale_cancel, _) = update_auth(
    model,
    DeviceAuthorizationCancelled("flow-old", Ok(anonymous_api_status())),
    emit,
  )
  assert_true(stale_cancel == model)

  let (expired, _) = update_auth(
    model,
    DeviceAuthorizationPolled(
      current,
      Err(
        GitHubRequestError::GitHubRequestError(
          "The GitHub device code expired.",
        ),
      ),
    ),
    emit,
  )
  assert_true(
    expired.review.auth is AuthFailed(message) && message.contains("expired"),
  )
}

///|
test "device sign-in retries a private repository load" {
  let reference = pull_reference("upstream", "private-project", "17")
  let flow_id = "flow-private"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let model = device_auth_test_model(
    auth_status_from_api(device_api_status(flow_id)),
    LoadFailed("private repository"),
    Some(reference),
  )
  let (retried, _) = update_auth(
    model,
    DeviceAuthorizationPolled(flow_id, Ok(signed_in_api_status("reviewer"))),
    emit,
  )
  assert_eq(retried.generation, 6)
  assert_true(retried.phase is LoadingPullMetadata(attempt=0, ..))
  assert_true(retried.review.auth is SignedIn(Some("reviewer")))
}

///|
test "top-level reducer routes every message domain" {
  let model = initial_model()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)

  let auth_msg : AuthMsg = DeviceCodeCopied("stale-flow")
  let (auth_routed, _) = update(model, Auth(auth_msg), emit)
  let (auth_direct, _) = update_auth(model, auth_msg, emit)
  assert_true(auth_routed == auth_direct)

  let review_msg : ReviewMsg = VisibilityChanged(true)
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
