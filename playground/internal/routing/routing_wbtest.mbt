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
      "https://example.com/moondiff/#/moonbit-community/moondiff/pull/017",
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
      "https://github.com/a/b/pull/0/files", "https://github.com/a/b/pull/017", "https://github.com:443/a/b/commit/abcdef1",
    ] {
    assert_true(parse_change_url(url) is Err(_), msg=url)
  }
}

///|
test "PR commit URL and hash routes preserve pull context" {
  for
    url in [
      "https://github.com/acme/widgets/pull/17/commits/abcdef1", "https://github.com/acme/widgets/pull/17/changes/abcdef1",
    ] {
    guard parse_change_url(url) is Ok(reference) else {
      fail("expected PR commit URL to parse")
    }
    assert_true(reference.target is PullCommit("17", "abcdef1"))
    assert_eq(
      playground_route(reference),
      "#/acme/widgets/pull/17/commits/abcdef1",
    )
    guard reference_from_playground_url(
        "https://example.test/\{playground_route(reference)}",
      )
      is Ok(Some(roundtrip)) else {
      fail("expected PR commit route to round-trip")
    }
    assert_true(roundtrip == reference)
  }
  for
    url in [
      "https://github.com/acme/widgets/pull/17", "https://github.com/acme/widgets/pull/17/files",
      "https://github.com/acme/widgets/pull/17/commits",
    ] {
    guard parse_change_url(url) is Ok(reference) else {
      fail("expected PR URL to parse")
    }
    assert_true(reference.target is PullRequest("17"))
  }
}
