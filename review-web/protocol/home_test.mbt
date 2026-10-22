///|
test "homepage read requests and lightweight pages roundtrip" {
  let requests : Array[@protocol.GitHubRequest] = [
    ViewerPullsGet({ kind: ReviewRequested, cursor: None, }),
    ViewerPullsGet({ kind: Authored, cursor: Some("opaque"), }),
    PullCommitsGet({
      owner: "upstream",
      repo: "repo",
      number: "42",
      cursor: None,
    }),
    PullCommitsGet({
      owner: "upstream",
      repo: "repo",
      number: "42",
      cursor: Some("opaque"),
    }),
  ]
  for request in requests {
    assert_false(request.is_write())
    assert_true(@protocol.decode_request(request.encode()) == request)
  }
  let results : Array[@protocol.RpcValue] = [
    ViewerPulls({
      items: [
        {
          owner: "upstream",
          repo: "repo",
          number: "42",
          title: "Draft PR",
          author: "me",
          updated_at: "2026-09-17T00:00:00Z",
          draft: true,
        },
      ],
      total_count: 1001,
      next_cursor: Some("next"),
      incomplete: Some("Retry search"),
    }),
    PullCommits({
      items: [
        {
          sha: "abcdef1",
          message: "Summary",
          author: "Author",
          committed_at: "2026-09-17T00:00:00Z",
        },
      ],
      total_count: 301,
      next_cursor: Some("next"),
      base_sha: "abcdef1",
      head_sha: "abcdef2",
    }),
  ]
  for value in results {
    roundtrip(@protocol.Response::Success(value~))
  }
}

///|
test "homepage requests reject arbitrary searches and invalid pagination" {
  let bad : Array[Json] = [
    {
      "v": 2,
      "request": {
        "$tag": "ViewerPullsGet",
        "0": { "kind": { "$tag": "Authored" }, "username": "someone" },
      },
    },
    {
      "v": 2,
      "request": {
        "$tag": "ViewerPullsGet",
        "0": { "kind": { "$tag": "Authored" }, "query": "is:closed" },
      },
    },
    {
      "v": 2,
      "request": {
        "$tag": "ViewerPullsGet",
        "0": { "kind": { "$tag": "TeamReview" } },
      },
    },
    @protocol.GitHubRequest::ViewerPullsGet({
      kind: Authored,
      cursor: Some(""),
    }).encode(),
    @protocol.GitHubRequest::PullCommitsGet({
      owner: "upstream",
      repo: "repo",
      number: "2147483648",
      cursor: None,
    }).encode(),
  ]
  for value in bad {
    let rejected = try {
      ignore(@protocol.decode_request(value))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
