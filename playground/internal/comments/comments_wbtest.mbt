///|
test "comment list arguments omit fields that do not apply to the target" {
  json_inspect(comment_list_args(pull_reference("upstream", "project", "17")), content={
    "owner": "upstream",
    "repo": "project",
    "kind": "pull",
    "number": "17",
  })
  json_inspect(
    comment_list_args(commit_reference("upstream", "project", "abcdef1")),
    content={
      "owner": "upstream",
      "repo": "project",
      "kind": "commit",
      "sha": "abcdef1",
    },
  )
  json_inspect(
    comment_list_args(
      pull_commit_reference("upstream", "project", "17", "abcdef1"),
    ),
    content={
      "owner": "upstream",
      "repo": "project",
      "kind": "pull_commit",
      "number": "17",
      "sha": "abcdef1",
    },
  )
}

///|
test "authentication DTOs map to review auth state and preserve device copy feedback" {
  assert_true(
    auth_status_from_api({
      authenticated: true,
      login: Some("octocat"),
      install_url: None,
      device_flow: None,
    })
    is SignedIn(login=Some("octocat"), install_url=None),
  )
  let pending : ApiAuthStatus = {
    authenticated: false,
    login: None,
    install_url: Some("https://github.com/apps/moondiff/installations/new"),
    device_flow: Some({
      flow_id: "flow-1",
      user_code: "ABCD-EFGH",
      verification_uri: "https://github.com/login/device",
      expires_in: 900,
      poll_after: 5,
    }),
  }
  guard auth_status_from_api(pending) is DeviceAuthorizing(device) else {
    fail("expected a pending device authorization")
  }
  assert_eq(device.flow_id, "flow-1")
  assert_true(device.copy_status is DeviceCodeCopyReady)
  guard auth_status_from_api_preserving(
      pending,
      DeviceAuthorizing({ ..device, copy_status: DeviceCodeCopyDone, }),
    )
    is DeviceAuthorizing(preserved) else {
    fail("expected the same device flow to remain active")
  }
  assert_true(preserved.copy_status is DeviceCodeCopyDone)
  guard auth_status_from_api_preserving(
      pending,
      DeviceCancelling({ ..device, copy_status: DeviceCodeCopyDone, }),
    )
    is DeviceCancelling(cancelling) else {
    fail("expected cancellation of the same device flow to be preserved")
  }
  assert_eq(cancelling.flow_id, "flow-1")
  assert_true(cancelling.copy_status is DeviceCodeCopyDone)
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
fn review_comment_fixture(
  id : Int,
  line? : Int = 2,
  side? : String = "RIGHT",
  position? : Int? = Some(3),
  commit_id? : String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  reply_to? : Int64? = None,
) -> ApiReviewComment {
  {
    id: Int64::from_int(id),
    body: "comment \{id}",
    html_url: "https://github.com/upstream/project/pull/17#discussion_r\{id}",
    created_at: "2026-08-18T08:00:00Z",
    user: Some({ login: "reviewer", }),
    path: "src/main.mbt",
    line: Some(line),
    side: Some(side),
    position,
    commit_id,
    in_reply_to_id: reply_to,
  }
}

///|
test "review threads group replies and mark every stale anchor condition outdated" {
  let view = review_test_view()
  let root = review_comment_fixture(1)
  let reply = review_comment_fixture(2, reply_to=Some(Int64::from_int(1)))
  let no_position = review_comment_fixture(3, position=None)
  let missing_anchor = review_comment_fixture(4, line=99, position=Some(99))
  let old_head = review_comment_fixture(
    5,
    commit_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  let threads = review_threads(view, [
    root, reply, no_position, missing_anchor, old_head,
  ])
  assert_eq(threads.length(), 4)
  assert_eq(threads[0].root.id, Int64::from_int(1))
  assert_eq(threads[0].replies.map(comment => comment.id), [Int64::from_int(2)])
  assert_eq(threads[0].file_index, Some(0))
  assert_false(threads[0].outdated)
  assert_true(threads[1].outdated)
  assert_true(threads[2].outdated)
  assert_true(threads[3].outdated)
}

///|
test "commit discussions use only canonical patch positions" {
  let view = review_test_view(
    target=Commit("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let comments : Array[ApiCommitComment] = [
    {
      id: Int64::from_int(10),
      body: "active",
      html_url: "https://github.com/upstream/project/commit/a#commitcomment-10",
      created_at: "2026-08-18T08:00:00Z",
      user: None,
      path: Some("src/main.mbt"),
      position: Some(3),
      line: Some(2),
    },
    {
      id: Int64::from_int(11),
      body: "outdated",
      html_url: "https://github.com/upstream/project/commit/a#commitcomment-11",
      created_at: "2026-08-18T08:00:00Z",
      user: None,
      path: Some("src/main.mbt"),
      position: Some(99),
      line: None,
    },
  ]
  let discussions = commit_discussions(view, comments)
  assert_eq(discussions.map(item => item.file_index), [Some(0), Some(0)])
  assert_false(discussions[0].outdated)
  assert_true(discussions[1].outdated)
}
