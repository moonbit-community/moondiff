///|
#warnings("-alert_unstable")
fn render_pull_merge(input : PullMergeInput) -> String {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(pull_merge_status_view(input, emit))
  })
}

///|
fn pull_merge_view_status() -> @protocol.ApiPullMergeStatus {
  {
    base_sha: "1111111111111111111111111111111111111111",
    head_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    open: true,
    draft: false,
    merged: false,
    mergeable: Some(true),
    rebaseable: Some(true),
    mergeable_state: "clean",
    ci_summary: Some(Failure),
    ci_checks: [
      {
        name: "MoonBit tests",
        state: Failure,
        description: "One target failed",
        details_url: Some("https://github.com/checks/1"),
        source: CheckRun,
      },
      {
        name: "unsafe link",
        state: Neutral,
        description: "No link should be rendered",
        details_url: Some("javascript:alert(1)"),
        source: CommitStatus,
      },
    ],
    ci_warnings: [
      "Commit statuses could not be read; CI results are incomplete.",
    ],
  }
}

///|
#warnings("-alert_unstable")
test "CI copy follows GitHub state wording and count grammar" {
  let success : @protocol.ApiCiCheck = {
    name: "build",
    state: Success,
    description: "success",
    details_url: None,
    source: CheckRun,
  }
  let failure : @protocol.ApiCiCheck = {
    ..success,
    state: Failure,
    description: "Native target failed",
  }
  assert_eq(ci_check_status_text(success), "Successful")
  assert_eq(ci_check_status_text(failure), "Failing — Native target failed")
  assert_eq(ci_checks_count_text([success]), "1 successful check")
  assert_eq(
    ci_checks_count_text([failure, success]),
    "1 failing and 1 successful checks",
  )
}

///|
#warnings("-alert_unstable")
test "merge card renders GitHub-style CI summary warnings and safe job links" {
  let rendered = render_pull_merge({
    state: {
      ..@application.PullMergeState::new(),
      status: Some(pull_merge_view_status()),
    },
    auth: @application.SignedIn(
      login=Some("alice"),
      user_id=Some("1"),
      install_url=None,
    ),
    snapshot_stale: false,
  })
  assert_true(
    rendered.contains("Some checks were not successful"),
    msg=rendered,
  )
  assert_true(rendered.contains("1 failing and 1 neutral checks"), msg=rendered)
  assert_true(rendered.contains("Show all checks"), msg=rendered)
  assert_true(rendered.contains("Hide all checks"), msg=rendered)
  assert_true(rendered.contains("<details"), msg=rendered)
  assert_false(rendered.contains("<details open"), msg=rendered)
  assert_true(rendered.contains("MoonBit tests"), msg=rendered)
  assert_true(rendered.contains("Failing — One target failed"), msg=rendered)
  assert_true(rendered.contains("CI results are incomplete"), msg=rendered)
  assert_true(
    rendered.contains("href=\"https://github.com/checks/1\""),
    msg=rendered,
  )
  assert_true(
    rendered.contains("aria-label=\"View MoonBit tests CI job\""),
    msg=rendered,
  )
  assert_false(rendered.contains("javascript:"), msg=rendered)
  assert_true(rendered.contains("Rebase and merge"), msg=rendered)
  assert_true(rendered.contains("aria-live=\"polite\""), msg=rendered)
  assert_true(
    rendered.contains("aria-label=\"Reload merge status\""),
    msg=rendered,
  )
}

///|
#warnings("-alert_unstable")
test "merge card distinguishes stale draft conflict unknown and merged states" {
  let base = pull_merge_view_status()
  let state = fn(status) {
    @application.PullMergeState::{
      ..@application.PullMergeState::new(),
      status: Some(status),
    }
  }
  let input = fn(status) {
    PullMergeInput::{
      state: state(status),
      auth: @application.SignedIn(
        login=Some("alice"),
        user_id=Some("1"),
        install_url=None,
      ),
      snapshot_stale: false,
    }
  }
  let anonymous = render_pull_merge({
    ..input(base),
    auth: @application.Anonymous(None),
  })
  assert_true(anonymous.contains("Sign in to merge"), msg=anonymous)
  let stale = render_pull_merge({ ..input(base), snapshot_stale: true, })
  assert_true(stale.contains("Load latest"), msg=stale)
  let draft = render_pull_merge(input({ ..base, draft: true, }))
  assert_true(draft.contains("draft ready for review"), msg=draft)
  assert_false(draft.contains("Rebase and merge"), msg=draft)
  let conflict = render_pull_merge(
    input({ ..base, mergeable: Some(false), rebaseable: Some(false), }),
  )
  assert_true(conflict.contains("has conflicts"), msg=conflict)
  assert_false(conflict.contains("Rebase and merge"), msg=conflict)
  let unknown = render_pull_merge(input({ ..base, mergeable: None, }))
  assert_true(unknown.contains("still calculating"), msg=unknown)
  let merged = render_pull_merge(input({ ..base, merged: true, open: false, }))
  assert_true(merged.contains("pull request is merged"), msg=merged)
  let blocked = render_pull_merge({
    ..input({ ..base, mergeable_state: "blocked", }),
    auth: @application.SignedIn(
      login=Some("alice"),
      user_id=Some("1"),
      install_url=None,
    ),
  })
  assert_true(blocked.contains("Repository rules currently block"), msg=blocked)
  assert_true(blocked.contains("disabled"), msg=blocked)
  let behind = render_pull_merge({
    ..input({ ..base, mergeable_state: "behind", }),
    auth: @application.SignedIn(
      login=Some("alice"),
      user_id=Some("1"),
      install_url=None,
    ),
  })
  assert_true(behind.contains("Rebase and merge"), msg=behind)
}

///|
#warnings("-alert_unstable")
test "merge region sits between discussion and changed files" {
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      shell_view(
        {
          home: false,
          generation: 1,
          landing: false,
          showing: true,
          message: "Review",
          drawer_open: false,
          preferred_width: 300,
          display: {
            mode: @change.Split,
            algorithm: @change.LexicalAlgorithm,
            ignore_comments: false,
            ignore_tests: false,
          },
        },
        [
          { region: @application.Discussion, id: "discussion", },
          { region: @application.PullMergeStatus, id: "merge", },
          { region: @application.File("src/main.mbt"), id: "file", },
        ],
      ),
    )
  })
  let discussion = rendered.find("id=\"discussion\"").unwrap_or(-1)
  let merge = rendered.find("id=\"merge\"").unwrap_or(-1)
  let file = rendered.find("id=\"file\"").unwrap_or(-1)
  assert_true(discussion >= 0 && discussion < merge, msg=rendered)
  assert_true(merge < file, msg=rendered)
}
