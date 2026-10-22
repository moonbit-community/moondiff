///|
fn range_navigation_model() -> Model {
  let model = navigation_review_model()
  let pull = { ..review_test_pull(), commits: Some(3), }
  let first = "b".repeat(40)
  let second = "c".repeat(40)
  let state = accept_pull_commit_page(
    range_state(pull.base.sha, pull.head.sha, Some(pull)),
    1,
    [
      {
        sha: first,
        commit: { message: "First", },
        parents: [{ sha: pull.base.sha, }],
      },
      {
        sha: second,
        commit: { message: "Second", },
        parents: [{ sha: first, }],
      },
      {
        sha: pull.head.sha,
        commit: { message: "Head", },
        parents: [{ sha: second, }],
      },
    ],
  )
  { ..model, range: Some(state), }
}

///|
test "selected interval target requires a PR and a complete valid ordered selection" {
  let model = range_navigation_model()
  let state = model.range.unwrap()
  let reference = model.route.unwrap()
  assert_eq(
    range_selected_path(reference, state),
    Some(
      "/upstream/project/pull/17/compare/\{state.base_sha}..\{state.head_sha}",
    ),
  )
  for
    invalid in [
      { ..state, from_sha: "invalid", },
      { ..state, from_sha: "b".repeat(7), },
      { ..state, to_sha: "d".repeat(40), },
      { ..state, from_sha: state.head_sha, },
      { ..state, from_sha: "c".repeat(40), to_sha: "b".repeat(40), },
      { ..state, loading_page: Some(2), },
      { ..state, next_page: Some(2), },
      { ..state, error: Some("incomplete"), },
      { ..state, total_commits: 4, },
      { ..state, commits: [], },
      { ..state, linear_commits: Some([]), },
      { ..state, linear_commits: None, },
    ] {
    assert_true(range_selected_path(reference, invalid) is None)
    let blocked = {
      ..model,
      range: Some(invalid),
      pull_merge: { ..model.pull_merge, submitting: true, },
    }
    for
      msg in [
        OpenSelected(model.generation),
        FromSelected(model.generation, invalid.from_sha),
        ToSelected(model.generation, invalid.to_sha),
      ] {
      assert_true(home_step(blocked, Range(msg)) == blocked)
    }
  }
  for
    target in [
      @github.commit_reference("upstream", "project", state.head_sha),
      @github.range_reference(
        "upstream",
        "project",
        state.base_sha,
        state.head_sha,
      ),
      @github.pull_range_reference(
        "upstream",
        "project",
        "17",
        state.base_sha,
        state.head_sha,
      ),
    ] {
    assert_true(range_selected_path(target, state) is None)
    let other = { ..model, route: Some(target), }
    assert_true(
      home_step(other, Range(OpenSelected(model.generation))) == other,
    )
  }
}

///|
test "range selection and activation ignore retired generations even on another PR" {
  let model = range_navigation_model()
  let current = {
    ..model,
    generation: model.generation + 1,
    route: Some(@github.pull_reference("upstream", "project", "18")),
    pull_merge: { ..model.pull_merge, submitting: true, },
  }
  for
    msg in [
      FromSelected(model.generation, "b".repeat(40)),
      ToSelected(model.generation, "c".repeat(40)),
      OpenSelected(model.generation),
    ] {
    let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
    assert_true(update_range(current, msg, emit).0 == current)
  }
}

///|
test "interval activation pins the latest accepted selection while a merge delays navigation" {
  let model = range_navigation_model()
  let generation = model.generation
  let blocked = {
    ..model,
    pull_merge: { ..model.pull_merge, submitting: true, },
  }
  let from = home_step(blocked, Range(FromSelected(generation, "b".repeat(40))))
  let to = home_step(from, Range(ToSelected(generation, "c".repeat(40))))
  // An old select's option can now be out of order. It must not alter the model.
  assert_true(
    home_step(to, Range(ToSelected(generation, "b".repeat(40)))) == to,
  )
  let opened = home_step(to, Range(OpenSelected(generation)))
  let path = "/upstream/project/pull/17/compare/\{"b".repeat(40)}..\{"c".repeat(40)}"
  assert_true(opened.navigation.pending is Some(Path(value)) && value == path)
  let changed = home_step(
    opened,
    Range(FromSelected(generation, model.range.unwrap().base_sha)),
  )
  assert_true(changed.navigation.pending == opened.navigation.pending)
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let success = {
    ..changed,
    pull_merge: { ..changed.pull_merge, submitting: false, },
  }
  assert_true(
    reconcile_navigation(changed, success, emit).0.navigation.pending is None,
  )
  let failure = {
    ..success,
    pull_merge: { ..success.pull_merge, error: Some("merge failed"), },
  }
  assert_true(navigation_write_failed(changed, failure))
  assert_true(
    reconcile_navigation(changed, failure, emit).0.navigation.pending is None,
  )
}

///|
test "interval activation retains its clicked destination until comment success and cancels on failure" {
  let model = range_navigation_model()
  let generation = model.generation
  let edited = home_step(
    home_step(model, Review(OpenOverallDraft)),
    Review(DraftBodyChanged("body")),
  )
  let posting = home_step(edited, Review(SubmitDraft))
  assert_true(navigation_blocked(posting))
  let selected = home_step(
    posting,
    Range(ToSelected(generation, "b".repeat(40))),
  )
  let opened = home_step(selected, Range(OpenSelected(generation)))
  let path = "/upstream/project/pull/17/compare/\{model.range.unwrap().base_sha}..\{"b".repeat(40)}"
  assert_true(opened.navigation.pending is Some(Path(value)) && value == path)
  let changed = home_step(
    opened,
    Range(ToSelected(generation, model.range.unwrap().head_sha)),
  )
  assert_true(changed.navigation.pending == opened.navigation.pending)
  let success = home_step(
    changed,
    Review(
      IssueCommentCreated(
        generation,
        changed.review.submission_id,
        Ok({
          id: 42L,
          body: "body",
          html_url: "https://github.com/upstream/project/pull/17#issuecomment-42",
          created_at: "2026-08-18T08:00:00Z",
          user: Some({ login: "reviewer", }),
        }),
      ),
    ),
  )
  assert_true(success.navigation.pending is None)
  assert_true(success.review.draft() is None)
  let failed = home_step(
    changed,
    Review(
      IssueCommentCreated(
        generation,
        changed.review.submission_id,
        Err(GitHubRequestError::GitHubRequestError("write failed")),
      ),
    ),
  )
  assert_true(failed.navigation.pending is None)
  assert_true(failed.route == changed.route)
  assert_true(
    failed.review.draft() is Some({ body: "body", error: Some(_), .. }),
  )
}
