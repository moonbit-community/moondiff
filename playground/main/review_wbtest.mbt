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
test "extension request errors retain diagnostics and format unknown codes neutrally" {
  let error : Error = ExtensionRequestError(
    status=400,
    code="invalid_arguments",
    detail="Missing RPC argument: sha",
  )
  guard error is ExtensionRequestError(status~, code~, detail~) else {
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
      ExtensionRequestError(
        status=403,
        code="rate_limit",
        detail="API rate limit exceeded",
      ),
    ),
    "GitHub API rate limit exceeded. Sign in or try again after the reset time.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError(
        status=401,
        code="authentication_required",
        detail="Bad credentials",
      ),
    ),
    "Your GitHub session expired. Sign in again, then retry.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError(
        status=404,
        code="not_found_or_not_installed",
        detail="Not Found",
      ),
    ),
    "GitHub could not access this repository. Sign in and install the GitHub App for private repositories.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError(
        status=403,
        code="permission_denied",
        detail="Resource not accessible by integration",
      ),
    ),
    "GitHub denied this action. Install the app for this repository and check its Pull requests permission.",
  )
  assert_eq(
    comment_failure_message(
      ExtensionRequestError(
        status=422,
        code="invalid_comment_anchor",
        detail="Validation Failed",
      ),
    ),
    "GitHub rejected this comment anchor. Refresh the diff and choose the line again.",
  )
  assert_eq(
    error_message(
      GitHubRequestError(
        "GitHub request failed: HTTP 403 API rate limit exceeded",
      ),
      true,
    ),
    "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later.",
  )
}

///|
test "fork pull revisions retain base and head repositories" {
  let reference = pull_reference("upstream", "project", "7")
  let pull = ApiPull::{
    title: "Fork change",
    html_url: "https://github.com/upstream/project/pull/7",
    base: {
      sha: "1111111111111111111111111111111111111111",
      repo: Some({ full_name: "upstream/project" }),
    },
    head: {
      sha: "2222222222222222222222222222222222222222",
      repo: Some({ full_name: "contributor/project-fork" }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
  let compare = ApiCompare::{
    merge_base_commit: { sha: "3333333333333333333333333333333333333333" },
  }
  let (old, new) = pull_revisions(reference, pull, compare)
  guard old is Some(old) else { fail("expected an old revision") }
  assert_true(old.repository == { owner: "upstream", repo: "project" })
  assert_eq(old.sha, "3333333333333333333333333333333333333333")
  assert_true(new.repository == { owner: "contributor", repo: "project-fork" })
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

///|
test "canonical patch maps sides, source lines, and multi-hunk positions" {
  let patch = parse_canonical_patch(
    "src/main.mbt",
    Some(
      "@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail\n@@ -10 +10,2 @@ fn later\n-old10\n+new10\n+extra\n\\ No newline at end of file",
    ),
  )
  assert_true(patch_is_commentable(patch))
  assert_eq(
    canonical_anchor(patch, Right, 1),
    Some({ path: "src/main.mbt", line: 1, side: Right, position: Some(1) }),
  )
  assert_eq(canonical_anchor(patch, Left, 2).unwrap().position, Some(2))
  assert_eq(canonical_anchor(patch, Right, 2).unwrap().position, Some(3))
  assert_eq(canonical_anchor(patch, Right, 3).unwrap().position, Some(4))
  assert_eq(canonical_anchor(patch, Left, 10).unwrap().position, Some(6))
  assert_eq(canonical_anchor(patch, Right, 10).unwrap().position, Some(7))
  assert_eq(canonical_anchor(patch, Right, 11).unwrap().position, Some(8))
  assert_eq(canonical_anchor(patch, Left, 1), None)
}

///|
test "canonical patch handles default counts and truly empty lines" {
  let patch = parse_canonical_patch(
    "empty.txt",
    Some("@@ -4 +7 @@\n-\n+\n\\ No newline at end of file"),
  )
  assert_eq(canonical_anchor(patch, Left, 4).unwrap().position, Some(1))
  assert_eq(canonical_anchor(patch, Right, 7).unwrap().position, Some(2))
}

///|
test "missing truncated and malformed patches are not commentable" {
  for
    patch in [
      None,
      Some(""),
      Some("@@ -1,2 +1,2 @@\n-old\n+new"),
      Some("@@ -1 +1 @@\n?bad"),
      Some("@@ -x +1 @@\n-old\n+new"),
      Some("diff --git a/a b/a\n@@ -1 +1 @@\n-old\n+new"),
    ] {
    assert_false(patch_is_commentable(parse_canonical_patch("a", patch)))
  }
}

///|
test "review rows only expose anchors present in the canonical patch" {
  let document = @tokdiff.line_diff(old=["context", "old", "tail"], new=[
    "context", "new", "tail",
  ])
  let patch = parse_canonical_patch(
    "src/main.mbt",
    Some("@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail"),
  )
  let rows = project_review_rows(4, "src/main.mbt", document, patch)
  assert_true(rows.length() >= 3)
  guard rows[0].new_line == Some(1) else {
    fail("expected the leading context row")
  }
  assert_eq(rows[0].old_anchor, None)
  assert_true(rows[0].new_anchor is Some(_))
  guard rows[1].old_line == Some(2) && rows[1].new_line == Some(2) else {
    fail("expected an aligned replacement row")
  }
  assert_true(rows[1].old_anchor is Some(_))
  assert_true(rows[1].new_anchor is Some(_))
  assert_eq(rows[1].file_index, 4)

  let disabled = project_review_rows(
    4,
    "src/main.mbt",
    document,
    parse_canonical_patch("src/main.mbt", None),
  )
  assert_true(
    disabled.all(row => row.old_anchor is None && row.new_anchor is None),
  )
}

///|
fn review_test_view(target? : ChangeTarget = PullRequest("17")) -> ChangeView {
  let reference = CommitRef::{ owner: "upstream", repo: "project", target }
  let repository = RepositoryRef::{ owner: "upstream", repo: "project" }
  let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (view, _) = finish_change(
    reference,
    Some({ repository, sha: "1111111111111111111111111111111111111111" }),
    { repository, sha: head },
    "Review fixture",
    canonical_github_url(reference),
    { additions: 1, deletions: 1, total: 2 },
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
    5,
    emit,
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
    backend_status: BackendMissing,
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
  for
    auth in [
      WebReadOnly,
      AuthChecking,
      Anonymous(None),
      DeviceAuthorizing(device),
      DeviceCancelling(device),
      AuthFailed("authentication failed"),
    ] {
    let model = review_test_model(auth)
    assert_false(review_can_comment(model.review))
    for
      msg in [
        OpenOverallDraft,
        OpenInlineDraft(0, anchor),
        OpenReplyDraft(Int64::from_int(20)),
      ] {
      let (blocked, _) = update(model, msg, emit)
      assert_true(blocked == model)
    }
  }

  let signed_in = review_test_model(SignedIn(Some("reviewer")))
  assert_true(review_can_comment(signed_in.review))
  let (overall, _) = update(signed_in, OpenOverallDraft, emit)
  guard overall.review.draft is Some(overall_draft) else {
    fail("expected an overall draft")
  }
  assert_true(overall_draft.kind is OverallDraft)
  let (inline, _) = update(signed_in, OpenInlineDraft(0, anchor), emit)
  guard inline.review.draft is Some(inline_draft) else {
    fail("expected an inline draft")
  }
  assert_true(
    inline_draft.kind is InlineDraft(0, selected) && selected == anchor,
  )
  let comment_id = Int64::from_int(20)
  let (reply, _) = update(signed_in, OpenReplyDraft(comment_id), emit)
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
  let (blocked, _) = update(with_draft, SubmitDraft, emit)
  guard blocked.review.draft is Some(draft) else {
    fail("expected the blocked draft to be retained")
  }
  assert_false(draft.submitting)
  assert_true(draft.error.unwrap().contains("Sign in with GitHub"))
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
    user: Some({ login: "reviewer" }),
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
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendMissing,
    analysis_status: AnalysisIdle,
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
      repo: Some({ full_name: "upstream/project" }),
    },
    head: {
      sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      repo: Some({ full_name: "upstream/project" }),
    },
    additions: 1,
    deletions: 1,
    changed_files: 1,
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (next, _) = update(
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

  let (stale, _) = update(
    next,
    CommentsLoaded(
      5,
      Ok({ issue_comments: [], review_comments: [], commit_comments: [] }),
    ),
    emit,
  )
  assert_true(stale == next)
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
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendMissing,
    analysis_status: AnalysisIdle,
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
    user: Some({ login: "reviewer" }),
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (posted, _) = update(model, IssueCommentCreated(5, Ok(created)), emit)
  assert_true(posted.review.draft is None)
  guard posted.review.comments is CommentsReady(bundle) else {
    fail("expected optimistic comments to stay visible")
  }
  assert_eq(bundle.issue_comments.map(comment => comment.id), [created.id])

  let (failed, _) = update(
    model,
    IssueCommentCreated(
      5,
      Err(
        ExtensionRequestError(
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
}
