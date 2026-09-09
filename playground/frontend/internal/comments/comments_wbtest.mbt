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
  side? : @protocol.CommentSide = Right,
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
    original_line: None,
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
  // GitHub may retain the original commit id while updating a valid anchor.
  assert_false(threads[3].outdated)
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
test "orphan replies form one thread after their root is deleted" {
  let view = review_test_view()
  let first = review_comment_fixture(2, reply_to=Some(1L))
  let second = review_comment_fixture(3, reply_to=Some(1L))
  let threads = review_threads(view, [second, first])
  assert_eq(threads.length(), 1)
  assert_eq(threads[0].root.id, 2L)
  assert_eq(threads[0].replies.map(c => c.id), [3L])
}
