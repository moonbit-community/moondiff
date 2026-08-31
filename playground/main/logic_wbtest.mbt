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
test "parse supported GitHub commit and pull request URL forms" {
  guard parse_change_url(
      "https://github.com/moonbit-community/moondiff/commit/aBcDeF1?diff=split#files",
    )
    is Ok(commit) else {
    fail("expected commit URL to parse")
  }
  assert_eq(commit.owner, "moonbit-community")
  assert_eq(commit.repo, "moondiff")
  assert_true(commit.target is Commit("aBcDeF1"))

  guard parse_change_url(
      "https://github.com/moonbitlang/core/pull/42/changes/0123456789abcdef",
    )
    is Ok(pr) else {
    fail("expected PR changes URL to parse")
  }
  assert_eq(pr.owner, "moonbitlang")
  assert_eq(pr.repo, "core")
  assert_true(pr.target is PullCommit("42", "0123456789abcdef"))
  assert_eq(
    canonical_github_url(pr),
    "https://github.com/moonbitlang/core/pull/42/commits/0123456789abcdef",
  )

  for
    url in [
      "https://github.com/moonbitlang/core/pull/4082", "https://github.com/moonbitlang/core/pull/4082/files?diff=split#discussion_r1",
    ] {
    guard parse_change_url(url) is Ok(reference) else {
      fail("expected pull request URL to parse: \{url}")
    }
    assert_eq(reference.owner, "moonbitlang")
    assert_eq(reference.repo, "core")
    assert_true(reference.target is PullRequest("4082"))
  }
}

///|
test "shared playground routes round-trip to canonical GitHub commit URLs" {
  let reference = commit_reference("moonbit-community", "moondiff", "aBcDeF1")
  assert_eq(
    playground_route(reference),
    "#/moonbit-community/moondiff/commit/aBcDeF1",
  )
  assert_eq(
    canonical_github_url(reference),
    "https://github.com/moonbit-community/moondiff/commit/aBcDeF1",
  )
  guard reference_from_playground_url(
      "https://example.github.io/moondiff/#/moonbit-community/moondiff/commit/aBcDeF1",
    )
    is Ok(Some(parsed)) else {
    fail("expected the shared route to parse")
  }
  assert_true(parsed == reference)
  let pull = pull_reference("moonbitlang", "core", "4082")
  assert_eq(playground_route(pull), "#/moonbitlang/core/pull/4082")
  assert_eq(
    canonical_github_url(pull),
    "https://github.com/moonbitlang/core/pull/4082",
  )
  guard reference_from_playground_url(
      "https://example.github.io/moondiff/#/moonbitlang/core/pull/4082",
    )
    is Ok(Some(parsed_pull)) else {
    fail("expected the shared pull request route to parse")
  }
  assert_true(parsed_pull == pull)
  assert_true(
    reference_from_playground_url("https://example.com/moondiff/") is Ok(None),
  )
  assert_true(
    reference_from_playground_url(
      "https://example.com/moondiff/#/moonbit-community/moondiff/pull/0",
    )
    is Err(_),
  )
  assert_true(
    reference_from_playground_url(
      "https://example.com/moondiff/#/bad owner/moondiff/commit/abcdef1",
    )
    is Err(_),
  )
}

///|
test "reject unsupported or malformed URLs" {
  for
    url in [
      "http://github.com/a/b/commit/abcdef1", "https://git.example.com/a/b/commit/abcdef1",
      "https://github.example.com/a/b/commit/abcdef1", "https://github.com/a/b/compare/abcdef1...abcdef2",
      "https://github.com/-bad/b/commit/abcdef1", "https://github.com/a/bad%2Frepo/commit/abcdef1",
      "https://github.com/a/b/commit/abcdef", "https://github.com/a/b/pull/nope/changes/abcdef1",
      "https://github.com/a/b/pull/0/changes/abcdef1", "https://github.com/a/b/pull/nope",
      "https://github.com/a/b/pull/0/files", "https://github.com:443/a/b/commit/abcdef1",
    ] {
    assert_true(parse_change_url(url) is Err(_), msg=url)
  }
}

///|
test "select MoonBit diff only when either path ends with lowercase mbt" {
  for
    file in [
      fixture_file("main.mbt", "modified"),
      fixture_file("new.txt", "renamed", previous_filename="old.mbt"),
      fixture_file("new.mbt", "renamed", previous_filename="old.txt"),
    ] {
    assert_true(file_diff_mode(file) is MoonBitDiff, msg=file.filename)
  }
  for
    file in [
      fixture_file("README.md", "modified"),
      fixture_file("types.mbti", "modified"),
      fixture_file("guide.mbt.md", "modified"),
      fixture_file("MAIN.MBT", "modified"),
      fixture_file("moon.pkg", "modified"),
      fixture_file("new.txt", "renamed", previous_filename="old.txt"),
    ] {
    assert_true(file_diff_mode(file) is LineDiff, msg=file.filename)
  }
}

///|
test "diff notices distinguish Whole and section-local fallbacks" {
  guard diff_notice([ParseError(sides=[Old], detail="old: parse error")], true)
    is Some(complete) else {
    fail("expected a complete fallback notice")
  }
  assert_eq(complete.class_name, "diff-notice fallback")
  assert_eq(complete.label, "Lexical fallback")
  assert_true(complete.message.contains("this entire file"))
  assert_true(complete.message.contains("old: parse error"))

  guard diff_notice([SyntaxPositionsOutOfBounds(sides=[Old, New])], true)
    is Some(position_complete) else {
    fail("expected a complete syntax-position fallback notice")
  }
  assert_true(
    position_complete.message.contains(
      "syntax positions out of bounds on the old and new sides",
    ),
  )

  guard diff_notice([GraphLimitExceeded(limit=3_000_000)], false)
    is Some(partial) else {
    fail("expected a section-local fallback notice")
  }
  assert_eq(partial.class_name, "diff-notice partial-fallback")
  assert_eq(partial.label, "Section lexical fallback")
  assert_true(partial.message.contains("Only this semantic section"))
  assert_true(partial.message.contains("graph limit exceeded"))

  guard diff_notice([SyntaxPositionsOutOfBounds(sides=[New])], false)
    is Some(position_partial) else {
    fail("expected a section-local syntax-position fallback notice")
  }
  assert_true(
    position_partial.message.contains(
      "syntax positions out of bounds on the new side",
    ),
  )
  assert_true(position_partial.message.contains("Only this semantic section"))

  assert_true(diff_notice([], true) is None)
  assert_true(diff_notice([], false) is None)
}

///|
test "raw content URLs percent-encode each path byte" {
  let reference = commit_reference("moonbit-community", "moondiff", "abcdef1")
  assert_eq(
    raw_url(reference, "abcdef1", "src/a b#中?.mbt"),
    "https://raw.githubusercontent.com/moonbit-community/moondiff/abcdef1/src/a%20b%23%E4%B8%AD%3F.mbt",
  )
}

///|
test "decode local GitHub fixtures and select the first merge parent" {
  let merge = decode_commit(
    read_fixture("playground/main/fixtures/commit_page1.json"),
  )
  assert_eq(merge.sha, "abcdef1234567890abcdef1234567890abcdef12")
  assert_eq(
    merge.commit.message,
    "Add playground\n\nRender public MoonBit commits.",
  )
  assert_eq(
    first_parent(merge),
    Some("1111111111111111111111111111111111111111"),
  )
  assert_eq(merge.files.length(), 3)
  assert_eq(merge.files[0].previous_filename, None)
  assert_eq(merge.files[1].previous_filename, Some("src/old_name.txt"))

  let root = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  assert_eq(first_parent(root), None)
  assert_eq(root.stats.additions, 2)
}

///|
test "decode pull request metadata and choose merge base and head" {
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let compare = decode_compare(
    read_fixture("playground/main/fixtures/pull_compare.json"),
  )
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
  assert_eq(pull.title, "Aggregate the whole pull request")
  assert_eq(pull.head.sha, "cccccccccccccccccccccccccccccccccccccccc")
  assert_eq(
    pull_merge_base(compare),
    "9999999999999999999999999999999999999999",
  )
  assert_true(same_pull_snapshot(pull, pull))
  assert_false(
    same_pull_snapshot(pull, {
      ..pull,
      head: { sha: "dddddddddddddddddddddddddddddddddddddddd", repo: None, },
    }),
  )
  assert_false(
    same_pull_snapshot(pull, {
      ..pull,
      base: { sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", repo: None, },
    }),
  )
  assert_false(same_pull_snapshot(pull, { ..pull, changed_files: 3, }))
  let stats = pull_stats(pull)
  assert_eq(stats.additions, 7)
  assert_eq(stats.deletions, 3)
  assert_eq(stats.total, 10)
  assert_eq(files.map(file => file.filename), ["src/first.mbt", "README.md"])
  assert_true(validate_pull_files(pull, files) is Ok(_))
}

///|
test "pagination appends file metadata and stops at GitHub's 30-page cap" {
  let first = [fixture_file("a.mbt", "modified")]
  let second = [fixture_file("b.mbt", "added")]
  let merged = merge_file_pages(first, second)
  assert_eq(merged.map(file => file.filename), ["a.mbt", "b.mbt"])
  assert_true(should_fetch_next_page(1, 100))
  assert_false(should_fetch_next_page(1, 99))
  assert_false(should_fetch_next_page(30, 100))
  assert_true(
    commit_api_url(commit_reference("a", "b", "abcdef1"), 30).has_suffix(
      "?per_page=100&page=30",
    ),
  )
  let pull = pull_reference("moonbitlang", "core", "4082")
  assert_eq(
    pull_api_url(pull),
    "https://api.github.com/repos/moonbitlang/core/pulls/4082",
  )
  assert_eq(
    compare_api_url(
      pull, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "cccccccccccccccccccccccccccccccccccccccc",
    ),
    "https://api.github.com/repos/moonbitlang/core/compare/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...cccccccccccccccccccccccccccccccccccccccc",
  )
  assert_true(
    pull_files_api_url(pull, 2).has_suffix("/files?per_page=100&page=2"),
  )
  assert_true(should_fetch_next_pull_page(1, 100, 100, Some(101)))
  assert_false(should_fetch_next_pull_page(1, 100, 100, Some(100)))
  assert_false(should_fetch_next_pull_page(1, 99, 99, Some(101)))
  assert_false(should_fetch_next_pull_page(30, 100, 3_000, Some(3_001)))
}

///|
test "pull request files must be complete and within GitHub's limit" {
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
  guard validate_pull_files({ ..pull, changed_files: 3_001, }, files)
    is Err(over_limit) else {
    fail("expected the 3,000-file limit to be rejected")
  }
  assert_true(over_limit.contains("3,000-file API limit"))
  guard validate_pull_files(pull, files[:1]) is Err(incomplete) else {
    fail("expected an incomplete file response to be rejected")
  }
  assert_true(incomplete.contains("returned 1 files"))
  assert_true(incomplete.contains("metadata reports 2"))
}

///|
test "added deleted renamed merge and root commits choose the correct raw sides" {
  let reference = commit_reference("owner", "repo", "abcdef1")
  let parent = Some("1111111")
  let added = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("new.mbt", "added"),
  )
  assert_eq(added.old_url, None)
  assert_true(added.new_url is Some(_))

  let deleted = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("old.mbt", "removed"),
  )
  assert_true(deleted.old_url is Some(_))
  assert_eq(deleted.new_url, None)

  let renamed = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("new.mbt", "renamed", previous_filename="old name.mbt"),
  )
  assert_true(renamed.old_url.unwrap().has_suffix("/old%20name.mbt"))
  assert_true(renamed.new_url.unwrap().has_suffix("/new.mbt"))

  let root = source_pair(
    reference,
    "2222222",
    None,
    fixture_file("main.mbt", "modified"),
  )
  assert_eq(root.old_url, None)
  assert_true(root.new_url is Some(_))
}

///|
test "source validation accepts Unicode and universal newlines" {
  for source in ["a\n名😀\n", "a\r\n名😀\r\n", "a\r名😀\r"] {
    guard check_source(@utf8.encode(source)) is Renderable(lines) else {
      fail("expected source to render")
    }
    assert_eq(lines, ["a", "名😀", ""])
  }
}

///|
test "source validation rejects invalid UTF-8, NUL, byte and line limits" {
  guard check_source([0xff]) is Rejected(invalid_utf8, true) else {
    fail("expected invalid UTF-8 to be rejected")
  }
  assert_true(invalid_utf8.contains("not valid UTF-8"))
  guard check_source(b"a\x00b") is Rejected(nul, true) else {
    fail("expected NUL to be rejected")
  }
  assert_true(nul.contains("NUL byte"))
  assert_true(
    check_source(Bytes::make(MAX_SOURCE_BYTES + 1, b'x')) is Rejected(_, false),
  )
  assert_true(
    check_source(@utf8.encode("\r".repeat(MAX_SOURCE_LINES)))
    is Rejected(_, false),
  )
}

///|
test "source validation allows exactly 20,000 CR-only lines" {
  guard check_source(@utf8.encode("\r".repeat(MAX_SOURCE_LINES - 1)))
    is Renderable(lines) else {
    fail("expected the line-limit boundary to render")
  }
  assert_eq(lines.length(), MAX_SOURCE_LINES)
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
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update(model, CommitPageLoaded(1, 1, Ok(fixture)), emit)
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
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = pull_test_model(
    reference,
    8,
    LoadingPullMetadata(reference~, attempt=0),
  )
  let (stale_generation, _) = update(
    loading,
    PullMetadataLoaded(7, 0, Ok(pull)),
    emit,
  )
  assert_true(stale_generation == loading)
  let (stale_attempt, _) = update(
    loading,
    PullMetadataLoaded(8, 1, Ok(pull)),
    emit,
  )
  assert_true(stale_attempt == loading)
  let (started, _) = update(loading, PullMetadataLoaded(8, 0, Ok(pull)), emit)
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

  let (over_limit, _) = update(
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
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let compare = decode_compare(
    read_fixture("playground/main/fixtures/pull_compare.json"),
  )
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
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
  let (wrong_page, _) = update(
    loading,
    PullFilesPageLoaded(7, 0, 2, Ok(files)),
    emit,
  )
  assert_true(wrong_page == loading)
  let (wrong_attempt, _) = update(
    loading,
    PullCompareLoaded(7, 1, Ok(compare)),
    emit,
  )
  assert_true(wrong_attempt == loading)
  let (after_files, _) = update(
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
  let (early_validation, _) = update(
    after_files,
    PullValidationLoaded(7, 0, Ok(pull)),
    emit,
  )
  assert_true(early_validation == after_files)
  let (validating, _) = update(
    after_files,
    PullCompareLoaded(7, 0, Ok(compare)),
    emit,
  )
  assert_true(validating.phase is ValidatingPullSnapshot(attempt=0, ..))
  let verified = { ..pull, title: "Verified pull title", additions: 11, }
  let (shown, _) = update(
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
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let compare = decode_compare(
    read_fixture("playground/main/fixtures/pull_compare.json"),
  )
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
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
  let (retrying, _) = update(
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
  let (stale_generation, _) = update(
    retrying,
    PullCompareLoaded(8, 1, Ok(compare)),
    emit,
  )
  assert_true(stale_generation == retrying)
  let (stale_compare, _) = update(
    retrying,
    PullCompareLoaded(9, 0, Ok(compare)),
    emit,
  )
  assert_true(stale_compare == retrying)
  let (stale_files, _) = update(
    retrying,
    PullFilesPageLoaded(9, 0, 1, Ok(files)),
    emit,
  )
  assert_true(stale_files == retrying)
  let (stale_files_generation, _) = update(
    retrying,
    PullFilesPageLoaded(8, 1, 1, Ok(files)),
    emit,
  )
  assert_true(stale_files_generation == retrying)
  let (stale_validation, _) = update(
    retrying,
    PullValidationLoaded(9, 0, Ok(latest)),
    emit,
  )
  assert_true(stale_validation == retrying)

  let latest_compare : ApiCompare = {
    merge_base_commit: { sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", },
  }
  let (with_compare, _) = update(
    retrying,
    PullCompareLoaded(9, 1, Ok(latest_compare)),
    emit,
  )
  let (validating_latest, _) = update(
    with_compare,
    PullFilesPageLoaded(9, 1, 1, Ok(files)),
    emit,
  )
  assert_true(validating_latest.phase is ValidatingPullSnapshot(attempt=1, ..))
  let (stale_validation_generation, _) = update(
    validating_latest,
    PullValidationLoaded(8, 1, Ok(latest)),
    emit,
  )
  assert_true(stale_validation_generation == validating_latest)
  let (shown, _) = update(
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
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let compare = decode_compare(
    read_fixture("playground/main/fixtures/pull_compare.json"),
  )
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
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
  let (failed, _) = update(
    validating,
    PullValidationLoaded(10, 1, Ok(changed_again)),
    emit,
  )
  assert_true(failed.phase is LoadFailed(PULL_CHANGED_ERROR))
}

///|
test "incomplete pull pagination retries once then keeps the incomplete error" {
  let reference = pull_reference("moonbitlang", "core", "4082")
  let pull = decode_pull(read_fixture("playground/main/fixtures/pull.json"))
  let compare = decode_compare(
    read_fixture("playground/main/fixtures/pull_compare.json"),
  )
  let files = decode_pull_files(
    read_fixture("playground/main/fixtures/pull_files.json"),
  )
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
  let (validating, _) = update(
    loading,
    PullFilesPageLoaded(11, 0, 1, Ok([files[0]])),
    emit,
  )
  assert_true(validating.phase is ValidatingPullSnapshot(attempt=0, ..))
  let (retrying, _) = update(
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
  let (incomplete, _) = update(
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
test "all files remain listed but only the first twenty MoonBit diffs auto-load" {
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  let files : Array[ApiFile] = []
  files.push(fixture_file("README.md", "added"))
  for index in 0..<21 {
    if index == 5 {
      files.push(
        fixture_file(
          "src/file_5.txt",
          "renamed",
          previous_filename="src/file_5.mbt",
        ),
      )
    } else {
      files.push(fixture_file("src/file_\{index}.mbt", "added"))
    }
    if index == 9 {
      files.push(fixture_file("assets/logo.bin", "added"))
    }
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let reference = commit_reference("example", "root", fixture.sha)
  let (view, _) = finish_commit(
    reference,
    reference_repository(reference),
    fixture,
    files,
    7,
    emit,
  )
  assert_eq(view.files.length(), files.length())
  assert_eq(
    view.files.map(state => state.file.filename),
    files.map(file => file.filename),
  )
  let mut moonbit_index = 0
  for state in view.files {
    match state.diff_mode {
      MoonBitDiff => {
        if moonbit_index < 20 {
          assert_true(state.expanded, msg=state.file.filename)
          assert_true(state.old_side is Ready([]), msg=state.file.filename)
          assert_true(state.new_side is Loading, msg=state.file.filename)
        } else {
          assert_false(state.expanded, msg=state.file.filename)
          assert_true(state.new_side is NotRequested, msg=state.file.filename)
        }
        moonbit_index += 1
      }
      LineDiff => {
        assert_false(state.expanded, msg=state.file.filename)
        assert_true(state.new_side is NotRequested, msg=state.file.filename)
      }
    }
  }
  assert_eq(moonbit_index, 21)

  let model = Model::{
    input: "",
    generation: 7,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Showing(view),
    route: Some(reference),
    share_url: None,
    copy_status: CopyReady,
    review: initial_review_state(),
  }
  let (after, _) = update(
    model,
    SourceLoaded(6, 0, New, Ok(("text/plain", @utf8.encode("stale")))),
    emit,
  )
  assert_true(after == model)
}

///|
fn diff_test_view(files : Array[ApiFile]) -> ChangeView raise {
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/commit_page1.json"),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (view, _) = finish_commit(
    commit_reference("example", "project", fixture.sha),
    { owner: "example", repo: "project", },
    fixture,
    files,
    9,
    emit,
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
test "MoonBit files cache all eight algorithm and filter combinations" {
  let file = fixture_file("src/filters.mbt", "modified")
  let mut cached = ready_test_file(
    file,
    [
      "/// old docs", "fn production() { old_value() }", "test \"sample\" { old_test() }",
    ],
    [
      "/// new docs", "fn production() { new_value() }", "test \"sample\" { new_test() }",
    ],
  )
  for algorithm in [LexicalAlgorithm, AstAlgorithm] {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        let key = CacheKey::MoonBit(algorithm, ignore_comments, ignore_tests)
        assert_true(cached.diff_cache.get(key) is None)
        cached = ensure_file_document(
          cached,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
        assert_true(cached.diff_cache.get(key) is Some(_))
      }
    }
  }
  for key in all_moonbit_cache_keys() {
    assert_true(cached.diff_cache.get(key) is Some(_))
  }
  assert_true(cached.diff_cache.get(Line) is None)
}

///|
test "line and MoonBit caches retain distinct semantic variants" {
  let text_file = ensure_file_document(
    ready_test_file(fixture_file("README.md", "modified"), ["old"], ["new"]),
    LexicalAlgorithm,
  )
  guard text_file.diff_cache.get(Line) is Some(Line(line_document)) else {
    fail("expected a line-diff cache")
  }
  assert_false(line_document.hunks.is_empty())

  let moonbit_file = ensure_file_document(
    ready_test_file(
      fixture_file("src/reorder.mbt", "modified"),
      ["fn first() {}", "fn second() {}"],
      ["fn second() {}", "fn first() {}"],
    ),
    AstAlgorithm,
  )
  guard moonbit_file.diff_cache.get(MoonBit(AstAlgorithm, false, false))
    is Some(MoonBit(document=TopLevel(top), status=Reordered)) else {
    fail("expected a semantic reorder cache")
  }
  assert_true(top.reordered)
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [1, 0])
  assert_true(
    top.sections.all(section => {
      semantic_section_fragment(section).document.hunks.is_empty()
    }),
  )
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
  let (switched, _) = update(
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
  let (switched_back, _) = update(
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
  let (toggled, _) = update(diff_test_model(view), ToggleIgnoreComments, emit)
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
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
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
  let (loaded, _) = update(loading, CommitPageLoaded(1, 1, Ok(fixture)), emit)
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
  let (toggled, _) = update(diff_test_model(view), ToggleIgnoreTests, emit)
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
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
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
  let (loaded, _) = update(loading, CommitPageLoaded(1, 1, Ok(fixture)), emit)
  assert_true(loaded.ignore_tests)
  assert_false(playground_route(reference).contains("ignore"))
}

///|
test "new source invalidates every MoonBit filter cache" {
  let file = fixture_file("src/change.mbt", "modified")
  let mut cached = ready_test_file(file, ["fn f() { old() }"], [
    "fn f() { new() }",
  ])
  for algorithm in [LexicalAlgorithm, AstAlgorithm] {
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
  let (updated, _) = update(
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
test "non-MoonBit line document is shared across algorithm switches" {
  let file = fixture_file("README.md", "modified")
  let line_key = CacheKey::Line
  let cached = ensure_file_document(
    ready_test_file(file, ["old"], ["new"]),
    LexicalAlgorithm,
  )
  guard cached.diff_cache.get(line_key) is Some(before) else {
    fail("expected line cache")
  }
  let after = ensure_file_document(
    cached,
    AstAlgorithm,
    ignore_comments=true,
    ignore_tests=true,
  )
  assert_true(after.diff_cache == cached.diff_cache)
  assert_true(after.diff_cache.get(line_key) == Some(before))
  for key in all_moonbit_cache_keys() {
    assert_true(after.diff_cache.get(key) is None)
  }
}
