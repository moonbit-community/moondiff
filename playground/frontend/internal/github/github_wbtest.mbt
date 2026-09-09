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
test "raw content URLs percent-encode each path byte" {
  let reference = commit_reference("moonbit-community", "moondiff", "abcdef1")
  assert_eq(
    raw_url(reference, "abcdef1", "src/a b#中?.mbt"),
    "https://raw.githubusercontent.com/moonbit-community/moondiff/abcdef1/src/a%20b%23%E4%B8%AD%3F.mbt",
  )
}

///|
test "decode local GitHub fixtures and select the first merge parent" {
  let merge = decode_commit(read_fixture("testdata/github/commit_page1.json"))
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

  let root = decode_commit(read_fixture("testdata/github/root_commit.json"))
  assert_eq(first_parent(root), None)
  assert_eq(root.stats.additions, 2)
}

///|
test "decode pull request metadata and choose merge base and head" {
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let compare = decode_compare(
    read_fixture("testdata/github/pull_compare.json"),
  )
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
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
  let pull = decode_pull(read_fixture("testdata/github/pull.json"))
  let files = decode_pull_files(read_fixture("testdata/github/pull_files.json"))
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
test "fork pull revisions retain base and head repositories" {
  let reference = pull_reference("upstream", "project", "7")
  let pull = ApiPull::{
    title: "Fork change",
    html_url: "https://github.com/upstream/project/pull/7",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "upstream/project", }),
    },
    head: {
      sha: "2222222222222222222222222222222222222222",
      repo: Some({ full_name: "contributor/project-fork", }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
  let compare = ApiCompare::{
    merge_base_commit: { sha: "3333333333333333333333333333333333333333", },
  }
  let (old, new) = pull_revisions(reference, pull, compare)
  guard old is Some(old) else { fail("expected an old revision") }
  assert_true(old.repository == { owner: "upstream", repo: "project", })
  assert_eq(old.sha, "3333333333333333333333333333333333333333")
  assert_true(new.repository == { owner: "contributor", repo: "project-fork", })
  assert_eq(new.sha, pull.head.sha)
  let pair = source_pair_for_revisions(Some(old), new, {
    filename: "src/main.mbt",
    previous_filename: None,
    status: "modified",
    additions: 1,
    deletions: 1,
    changes: 2,
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  })
  assert_true(pair.old_url.unwrap().contains("/upstream/project/"))
  assert_true(pair.new_url.unwrap().contains("/contributor/project-fork/"))
}
