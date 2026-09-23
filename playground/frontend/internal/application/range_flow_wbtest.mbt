///|
fn range_test_compare(
  base : String,
  head : String,
  merge : String,
  total : Int,
  count : Int,
  files : Array[ApiFile]?,
) -> ApiRangeCompare {
  let commits : Array[@protocol.ApiRangeCommit] = []
  for i in 0..<count {
    let suffix = i.to_string()
    commits.push({
      sha: if i == total - 1 {
        head
      } else {
        "0".repeat(40 - suffix.length()) + suffix
      },
      commit: { message: "Commit \{i}", },
      parents: [{ sha: base, }],
    })
  }
  {
    base_commit: {
      sha: base,
      commit: { message: "Base commit", },
      parents: [],
    },
    merge_base_commit: { sha: merge, },
    total_commits: total,
    commits,
    files,
  }
}

///|
test "PR interval endpoints follow commit order" {
  let base = "a".repeat(40)
  let first = "b".repeat(40)
  let second = "c".repeat(40)
  let head = "d".repeat(40)
  let state = {
    ..range_state(base, head, None),
    commits: [
      { sha: first, commit: { message: "First", }, parents: [{ sha: base, }], },
      {
        sha: second,
        commit: { message: "Second", },
        parents: [{ sha: first, }],
      },
      { sha: head, commit: { message: "Head", }, parents: [{ sha: second, }], },
    ],
  }
  assert_true(range_commit_after(state, base, first))
  assert_true(range_commit_after(state, first, second))
  assert_true(range_commit_after(state, second, head))
  assert_true(!range_commit_after(state, second, first))
  assert_true(!range_commit_after(state, first, first))
  assert_true(!range_commit_after(state, first, base))
  assert_true(!range_commit_after(state, "e".repeat(40), head))
  assert_true(!range_commit_after(state, head, head))
}

///|
test "PR selector requires a complete single-parent chain and follows parent order" {
  let base = "a".repeat(40)
  let first = "b".repeat(40)
  let second = "c".repeat(40)
  let head = "d".repeat(40)
  let first_commit : @protocol.ApiRangeCommit = {
    sha: first,
    commit: { message: "First", },
    parents: [{ sha: base, }],
  }
  let second_commit : @protocol.ApiRangeCommit = {
    sha: second,
    commit: { message: "Second", },
    parents: [{ sha: first, }],
  }
  let head_commit : @protocol.ApiRangeCommit = {
    sha: head,
    commit: { message: "Head", },
    parents: [{ sha: second, }],
  }
  let shuffled = [head_commit, first_commit, second_commit]
  guard pull_linear_chain(base, head, shuffled) is Some(ordered) else {
    fail("the complete chain should be supported")
  }
  assert_eq(ordered.map(commit => commit.sha), [first, second, head])
  let pull = {
    ..review_test_pull(),
    base: { ..review_test_pull().base, sha: base, },
    head: { ..review_test_pull().head, sha: head, },
    commits: Some(3),
  }
  let pending = {
    ..range_state(base, head, Some(pull)),
    commits: shuffled,
    total_commits: 3,
    loading_page: None,
    next_page: Some(2),
  }
  assert_false(range_pull_selector_ready(pending))
  assert_false(range_pull_history_unsupported(pending))
  let ready = { ..pending, next_page: None, linear_commits: Some(ordered), }
  assert_true(range_pull_selector_ready(ready))
  assert_true(range_commit_after(ready, first, second))
  assert_false(range_commit_after(ready, head, first))
  let unsupported = { ..ready, linear_commits: None, }
  assert_false(range_pull_selector_ready(unsupported))
  assert_true(range_pull_history_unsupported(unsupported))
  assert_true(
    pull_linear_chain(base, head, [first_commit, head_commit]) is None,
  )
  assert_true(
    pull_linear_chain(base, head, [
      first_commit,
      { ..second_commit, parents: [{ sha: base, }], },
      head_commit,
    ])
    is None,
  )
  assert_true(
    pull_linear_chain(base, head, [
      first_commit,
      second_commit,
      { ..head_commit, parents: [{ sha: second, }, { sha: first, }], },
    ])
    is None,
  )
}

///|
test "range pages require exact base and ancestry" {
  let base = "a".repeat(40)
  let head = "b".repeat(40)
  let state = range_state(base, head, None)
  let valid = range_test_compare(base, head, base, 1, 1, Some([]))
  assert_true(range_page_error(state, 1, valid) is None)
  let accepted = accept_range_page(state, 1, valid)
  assert_eq(accepted.base_sha, base)
  assert_eq(accepted.head_sha, head)
  assert_eq(accepted.next_page, None)
  let unrelated = { ..valid, merge_base_commit: { sha: "c".repeat(40), }, }
  assert_true(range_page_error(state, 1, unrelated) is Some(_))
  assert_true(
    range_page_error(state, 1, {
      ..valid,
      base_commit: { ..valid.base_commit, sha: head, },
    })
    is Some(_),
  )
  assert_true(
    range_page_error(state, 1, {
      ..valid,
      commits: [{ sha: base, commit: { message: "wrong", }, parents: [], }],
    })
    is Some(_),
  )
  assert_true(
    range_page_error(state, 1, { ..valid, total_commits: 0, commits: [], })
    is Some(_),
  )
}

///|
test "empty interval and 300-file boundary never expose a partial review" {
  let sha = "a".repeat(40)
  let state = range_state(sha, sha, None)
  let empty = range_test_compare(sha, sha, sha, 0, 0, Some([]))
  assert_true(range_page_error(state, 1, empty) is None)
  let accepted = accept_range_page(state, 1, empty)
  assert_eq(accepted.total_commits, 0)
  assert_eq(accepted.next_page, None)
  let files : Array[ApiFile] = []
  for i in 0..<300 {
    files.push({
      filename: "file-\{i}.mbt",
      previous_filename: None,
      status: "modified",
      additions: 1,
      deletions: 1,
      changes: 2,
      patch: None,
    })
  }
  let limit = accept_range_page(state, 1, { ..empty, files: Some(files), })
  assert_true(limit.too_many_files)
  assert_true(
    !accept_range_page(state, 1, {
      ..empty,
      files: Some(files[:299].to_owned()),
    }).too_many_files,
  )
}

///|
test "range commits page through the pinned endpoint and reject short pages" {
  let base = "a".repeat(40)
  let head = "b".repeat(40)
  let state = range_state(base, head, None)
  let first = range_test_compare(base, head, base, 101, 100, Some([]))
  assert_true(range_page_error(state, 1, first) is None)
  let accepted = accept_range_page(state, 1, first)
  assert_eq(accepted.next_page, Some(2))
  let second = {
    ..range_test_compare(base, head, base, 101, 1, None),
    commits: [
      { sha: head, commit: { message: "last", }, parents: [{ sha: base, }], },
    ],
  }
  assert_true(range_page_error(accepted, 2, second) is None)
  let completed = accept_range_page(accepted, 2, second)
  assert_eq(completed.commits.length(), 101)
  assert_eq(completed.next_page, None)
  assert_true(range_page_error(state, 1, { ..first, commits: [], }) is Some(_))
  assert_true(
    range_page_error(accepted, 2, { ..second, total_commits: 102, }) is Some(_),
  )
  assert_true(
    range_page_error(accepted, 2, {
      ..second,
      commits: [{ sha: base, commit: { message: "wrong", }, parents: [], }],
    })
    is Some(_),
  )
}

///|
test "interval review waits for the final compare page" {
  let base = "a".repeat(40)
  let head = "b".repeat(40)
  let reference = @github.range_reference("alice", "repo", base, head)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (loading, _) = begin_change_load(initial_model(), reference, emit)
  let first = range_test_compare(base, head, base, 101, 100, Some([]))
  let (waiting, _) = update_range(
    loading,
    RangePageLoaded(loading.generation, 1, Ok(first)),
    emit,
  )
  assert_true(waiting.phase is LoadingRange(_))
  assert_true(waiting.range is Some({ loading_page: Some(2), .. }))
  let second = {
    ..range_test_compare(base, head, base, 101, 1, None),
    commits: [
      { sha: head, commit: { message: "Last", }, parents: [{ sha: base, }], },
    ],
  }
  let (shown, _) = update_range(
    waiting,
    RangePageLoaded(waiting.generation, 2, Ok(second)),
    emit,
  )
  assert_true(shown.phase is Showing(_))
  assert_true(shown.range is Some({ loading_page: None, next_page: None, .. }))
}

///|
fn pull_page_items(
  start : Int,
  count : Int,
  total : Int,
  head : String,
) -> Array[@protocol.ApiRangeCommit] {
  let items : Array[@protocol.ApiRangeCommit] = []
  for i in start..<(start + count) {
    let index = i.to_string()
    items.push({
      sha: if i == total - 1 {
        head
      } else {
        "0".repeat(40 - index.length()) + index
      },
      commit: { message: "Commit \{i}", },
      parents: [
        {
          sha: if i == 0 {
            "1".repeat(40)
          } else {
            let previous = (i - 1).to_string()
            "0".repeat(40 - previous.length()) + previous
          },
        },
      ],
    })
  }
  items
}

///|
test "PR commit API pages cover 100 and 250 commits with snapshot checks" {
  for total in [100, 250] {
    let pull = { ..review_test_pull(), commits: Some(total), }
    let mut state = {
      ..range_state(pull.base.sha, pull.head.sha, Some(pull)),
      loading_page: None,
      next_page: Some(1),
    }
    let pages = (total + 99) / 100
    for page in 1..<=pages {
      let count = Int::min(100, total - state.commits.length())
      let items = pull_page_items(
        state.commits.length(),
        count,
        total,
        pull.head.sha,
      )
      assert_true(pull_commit_page_error(state, page, items, pull) is None)
      state = accept_pull_commit_page(state, page, items)
    }
    assert_eq(state.commits.length(), total)
    assert_eq(state.next_page, None)
    assert_eq(state.commits[total - 1].sha, pull.head.sha)
    assert_true(state.linear_commits is Some(_))
  }
}

///|
test "PR commit pages reject changed snapshots and incomplete lists" {
  let pull = { ..review_test_pull(), commits: Some(101), }
  let state = range_state(pull.base.sha, pull.head.sha, Some(pull))
  let items = pull_page_items(0, 100, 101, pull.head.sha)
  assert_true(pull_commit_page_error(state, 1, items, pull) is None)
  assert_true(
    pull_commit_page_error(state, 1, items[:99].to_owned(), pull) is Some(_),
  )
  assert_true(
    pull_commit_page_error(state, 1, items, { ..pull, commits: Some(102), })
    is Some(_),
  )
  assert_true(
    pull_commit_page_error(state, 1, items, {
      ..pull,
      head: { ..pull.head, sha: "b".repeat(40), },
    })
    is Some(_),
  )
  assert_true(
    pull_commit_page_error(state, 1, items, {
      ..pull,
      base: { ..pull.base, repo: None, },
    })
    is Some(_),
  )
  let accepted = accept_pull_commit_page(state, 1, items)
  let last_page = pull_page_items(100, 1, 101, pull.head.sha)
  assert_true(pull_commit_page_error(accepted, 2, last_page, pull) is None)
  assert_true(
    pull_commit_page_error(
      accepted,
      2,
      [{ sha: "b".repeat(40), commit: { message: "wrong", }, parents: [], }],
      pull,
    )
    is Some(_),
  )
}

///|
test "old interval replies are ignored after navigation" {
  let reference = @github.range_reference(
    "alice",
    "repo",
    "a".repeat(40),
    "b".repeat(40),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (loading, _) = begin_change_load(initial_model(), reference, emit)
  let old_generation = loading.generation
  let (next, _) = begin_change_load(
    loading,
    @github.commit_reference("alice", "repo", "c".repeat(40)),
    emit,
  )
  let data = range_test_compare(
    "a".repeat(40),
    "b".repeat(40),
    "a".repeat(40),
    0,
    0,
    Some([]),
  )
  let (ignored, _) = update_range(
    next,
    RangePageLoaded(old_generation, 1, Ok(data)),
    emit,
  )
  assert_true(ignored == next)
  let (ignored_sha, _) = update_range(
    next,
    RangeShaResolved(old_generation, true, false, Ok("a".repeat(40))),
    emit,
  )
  assert_true(ignored_sha == next)
}

///|
test "short interval route becomes a fixed full-SHA empty comparison" {
  let sha = "a".repeat(40)
  let reference = @github.range_reference("alice", "repo", "aaaaaaa", "aaaaaaa")
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (loading, _) = begin_change_load(initial_model(), reference, emit)
  let (base_resolved, _) = update_range(
    loading,
    RangeShaResolved(loading.generation, true, false, Ok(sha)),
    emit,
  )
  let (head_resolved, _) = update_range(
    base_resolved,
    RangeShaResolved(loading.generation, false, false, Ok(sha)),
    emit,
  )
  let response = range_test_compare(sha, sha, sha, 0, 0, Some([]))
  let (finished, _) = update_range(
    head_resolved,
    RangePageLoaded(loading.generation, 1, Ok(response)),
    emit,
  )
  guard finished.route is Some(route) && finished.phase is Showing(view) else {
    fail("expected the empty interval to show")
  }
  assert_true(route.target is Range(_, _))
  assert_eq(view.total_files, 0)
  assert_eq(view.sha, sha)
  assert_true(@routing.playground_route(route).contains("\{sha}..\{sha}"))
}

///|
test "failed pull interval retries its route instead of its display URL" {
  let base = "a".repeat(40)
  let head = "b".repeat(40)
  let reference = @github.pull_range_reference(
    "upstream", "repo", "17", base, head,
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let failed = {
    ..initial_model(),
    input: canonical_github_url(reference),
    route: Some(reference),
    phase: LoadFailed("unavailable"),
    generation: 3,
  }
  let (retry, _) = update_ui(failed, RetryRoute, emit)
  assert_eq(retry.generation, 4)
  assert_true(retry.route == Some(reference))
  assert_true(retry.phase is LoadingRangePullMetadata(_))
  assert_eq(retry.range.map(state => state.base_sha), Some(base))
  let no_route = { ..failed, route: None, input: "not a URL", }
  let (invalid, _) = update_ui(no_route, RetryRoute, emit)
  assert_eq(invalid.generation, 4)
  assert_true(invalid.phase is LoadFailed(_))
}

///|
test "pull interval form keeps its PR route and canonicalizes untouched short SHAs" {
  let base = "1".repeat(40)
  let head = "a".repeat(40)
  let reference = @github.pull_range_reference(
    "upstream", "project", "17", "1111111", "aaaaaaa",
  )
  let pull = { ..review_test_pull(), commits: Some(1), }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let loading = {
    ..initial_model(),
    input: canonical_github_url(reference),
    route: Some(reference),
    generation: 3,
    phase: LoadingRange(reference~),
    range: Some(range_state(base, head, Some(pull))),
  }
  let response = range_test_compare(base, head, base, 1, 1, Some([]))
  let (shown, _) = update_range(
    loading,
    RangePageLoaded(loading.generation, 1, Ok(response)),
    emit,
  )
  let canonical = @github.pull_range_reference(
    "upstream", "project", "17", base, head,
  )
  assert_true(shown.route == Some(canonical))
  assert_eq(shown.input, canonical_github_url(canonical))
  let (submitted, _) = update_ui(shown, Submit, emit)
  assert_true(submitted.route == Some(canonical))
  assert_true(submitted.phase is LoadingRangePullMetadata(_))
  assert_eq(submitted.generation, shown.generation + 1)

  let edited_url = "https://github.com/other/repo/pull/18"
  let edited = update_ui(loading, InputChanged(edited_url), emit).0
  let (edited_shown, _) = update_range(
    edited,
    RangePageLoaded(edited.generation, 1, Ok(response)),
    emit,
  )
  assert_eq(edited_shown.input, edited_url)
  let (opened, _) = update_ui(edited_shown, Submit, emit)
  assert_true(
    opened.route == Some(@github.pull_reference("other", "repo", "18")),
  )
  assert_true(opened.phase is LoadingPullMetadata(_))
}
