///|
fn[T : FromJson + ToJson] roundtrip(value : T) -> Unit raise {
  let json = ToJson::to_json(value)
  let decoded : T = @protocol.decode(@json.parse(json.stringify()))
  assert_true(ToJson::to_json(decoded) == json)
}

///|
test "all thirteen requests roundtrip and classify writes" {
  let requests : Array[@protocol.GitHubRequest] = [
    CommitGet({ owner: "alice", repo: "repo", sha: "123abcd", page: 1, }),
    PullGet({ owner: "alice", repo: "repo", number: "42", }),
    CompareGet({
      owner: "alice",
      repo: "repo",
      base: "123abcd",
      head: "abcdef0",
    }),
    PullFiles({ owner: "alice", repo: "repo", number: "42", page: 2, }),
    ContentGet({
      owner: "alice",
      repo: "repo",
      path: "目录/file.mbt",
      revision: "123abcd",
    }),
    CommentsList({ owner: "alice", repo: "repo", target: Pull(number="42"), }),
    IssueCommentCreate({
      owner: "alice",
      repo: "repo",
      number: "42",
      body: "hello",
    }),
    ReviewCommentCreate({
      owner: "alice",
      repo: "repo",
      number: "42",
      commit_id: "123abcd",
      path: "a.mbt",
      line: 2147483647,
      side: Left,
      body: "hello",
    }),
    CommitCommentCreate({
      owner: "alice",
      repo: "repo",
      sha: "123abcd",
      path: "a.mbt",
      position: 1,
      body: "hello",
    }),
    ReviewReplyCreate({
      owner: "alice",
      repo: "repo",
      number: "42",
      comment_id: 9007199254740993L,
      body: "reply",
    }),
    IssueCommentDelete({
      owner: "alice",
      repo: "repo",
      comment_id: 9223372036854775807L,
    }),
    ReviewCommentDelete({ owner: "alice", repo: "repo", comment_id: 1, }),
    CommitCommentDelete({ owner: "alice", repo: "repo", comment_id: 1, }),
  ]
  for i, request in requests {
    assert_true(@protocol.decode_request(request.encode()) == request)
    assert_eq(request.is_write(), i >= 6)
  }
  for
    target in [
      @protocol.CommentTarget::Commit(sha="123abcd"),
      PullCommit(number="42", sha="123abcd"),
    ] {
    let request : @protocol.GitHubRequest = CommentsList({
      owner: "alice",
      repo: "repo",
      target,
    })
    assert_true(@protocol.decode_request(request.encode()) == request)
  }
}

///|
test "every RPC result and response envelope roundtrips including int64 ids" {
  let user : @protocol.ApiCommentUser = { login: "alice", }
  let issue : @protocol.ApiIssueComment = {
    id: 9007199254740993L,
    body: "hello",
    html_url: "https://github.com/comment/1",
    created_at: "today",
    user: Some(user),
  }
  let review : @protocol.ApiReviewComment = {
    id: 9223372036854775807L,
    body: "review",
    html_url: "url",
    created_at: "today",
    user: None,
    path: "a.mbt",
    line: Some(1),
    original_line: None,
    side: Some(Right),
    position: Some(1),
    commit_id: "123abcd",
    in_reply_to_id: Some(issue.id),
  }
  let commit : @protocol.ApiCommitComment = {
    id: 1,
    body: "commit",
    html_url: "url",
    created_at: "today",
    user: Some(user),
    path: None,
    position: None,
    line: None,
  }
  let file : @protocol.ApiFile = {
    filename: "a.mbt",
    previous_filename: None,
    status: "added",
    additions: 1,
    deletions: 0,
    changes: 1,
    patch: Some("+hello"),
  }
  let values : Array[@protocol.RpcValue] = [
    Commit({
      sha: "123abcd",
      html_url: "url",
      commit: { message: "commit", },
      parents: [],
      stats: { additions: 1, deletions: 0, total: 1, },
      files: [file],
    }),
    Pull({
      title: "pull",
      html_url: "url",
      base: { sha: "123abcd", repo: Some({ full_name: "alice/repo", }), },
      head: { sha: "abcdef0", repo: None, },
      additions: 1,
      deletions: 0,
      changed_files: 1,
    }),
    Compare({ merge_base_commit: { sha: "123abcd", }, }),
    Files([file]),
    Content({ base64: "aGk=", size: 2, content_type: "text/plain", }),
    Comments({
      issue_comments: [issue],
      review_comments: [review],
      commit_comments: [commit],
    }),
    IssueComment(issue),
    ReviewComment(review),
    CommitComment(commit),
    Deleted({ deleted: true, }),
  ]
  for value in values {
    roundtrip(@protocol.Response::Success(value~))
  }
  roundtrip(
    (
      @protocol.Response::Failure(error={
        status: 403,
        code: "permission_denied",
        message: "No access",
      }) : @protocol.Response[@protocol.RpcValue]),
  )
  roundtrip((@protocol.Response::Success(value=()) : @protocol.Response[Unit]))
  assert_true(issue.to_json() is { "id": "9007199254740993", .. })
}

///|
test "authentication phases and device responses roundtrip" {
  for
    phase in [
      @protocol.Starting,
      Pending,
      Verifying,
      Completed,
      Cancelled,
      Expired,
      Denied,
      Failed,
    ] {
    let status : @protocol.ApiAuthStatus = {
      authenticated: false,
      csrf_token: "csrf",
      login: None,
      user_id: None,
      install_url: Some("url"),
      device_flow: Some({
        id: "attempt-0000000000",
        phase,
        user_code: "CODE",
        verification_uri: "url",
        expires_at: 2000000000,
        retry_after: 5,
        message: "",
      }),
    }
    roundtrip(@protocol.Response::Success(value=status))
    roundtrip(
      @protocol.Response::Success(value=@protocol.DeviceResponse::{
        request_id: "attempt-0000000000",
        status,
      }),
    )
  }
  roundtrip(@protocol.DeviceStart::{ attempt_id: "attempt-0000000000", })
  roundtrip(@protocol.DeviceAuthorization::{
    authorization_id: "attempt-0000000000",
  })
}

///|
fn reject(value : Json) -> Unit raise {
  try @protocol.decode_request(value) catch {
    _ => ()
  } noraise {
    _ => fail("Accepted invalid request")
  }
}

///|
test "strict requests reject unknown tags versions extra missing fractional and out of range fields" {
  for
    text in [
      "{\"v\":1,\"request\":{\"$tag\":\"PullGet\",\"0\":{\"owner\":\"alice\",\"repo\":\"repo\",\"number\":\"1\"}}}",
      "{\"v\":2,\"request\":{\"$tag\":\"Unknown\"}}", "{\"v\":2,\"request\":{\"$tag\":\"CommitGet\",\"0\":{\"owner\":\"alice\",\"repo\":\"repo\",\"sha\":\"123abcd\"}}}",
    ] {
    reject(@json.parse(text))
  }
  for page in [0.0, -1.0, 1.5, 10001.0, 2147483648.0, 4294967297.0] {
    reject({
      "v": 2,
      "request": {
        "$tag": "CommitGet",
        "0": {
          "owner": "alice",
          "repo": "repo",
          "sha": "123abcd",
          "page": page,
        },
      },
    })
  }
  reject({
    "v": 2.5,
    "request": {
      "$tag": "PullGet",
      "0": { "owner": "alice", "repo": "repo", "number": "1" },
    },
  })
  reject({
    "v": 2,
    "extra": false,
    "request": {
      "$tag": "PullGet",
      "0": { "owner": "alice", "repo": "repo", "number": "1" },
    },
  })
  reject({
    "v": 2,
    "request": {
      "$tag": "PullGet",
      "extra": false,
      "0": { "owner": "alice", "repo": "repo", "number": "1" },
    },
  })
  reject({
    "v": 2,
    "request": {
      "$tag": "PullGet",
      "0": { "owner": "alice", "repo": "repo", "number": "1", "extra": false },
    },
  })
  for
    id in [
      "0", "-1", "01", "1.5", "9223372036854775808", "999999999999999999999",
    ] {
    reject({
      "v": 2,
      "request": {
        "$tag": "ReviewCommentDelete",
        "0": { "owner": "alice", "repo": "repo", "comment_id": id },
      },
    })
    reject({
      "v": 2,
      "request": {
        "$tag": "PullGet",
        "0": { "owner": "alice", "repo": "repo", "number": id },
      },
    })
  }
  reject({
    "v": 2,
    "request": {
      "$tag": "ReviewCommentDelete",
      "0": {
        "owner": "alice",
        "repo": "repo",
        "comment_id": 9007199254740992.0,
      },
    },
  })
}

///|
test "semantic validation rejects unsafe repository paths revisions comments and line positions" {
  for
    path in [
      "",
      "../file",
      "a//b",
      "/root",
      "a/./b",
      "a\u0000b",
      "a/../b",
      "a/",
      ".",
      "..",
      "a".repeat(4097),
    ] {
    reject(
      @protocol.GitHubRequest::ContentGet({
        owner: "alice",
        repo: "repo",
        path,
        revision: "123abcd",
      }).encode(),
    )
  }
  for
    (owner, repo, sha) in [
      ("-alice", "repo", "123abcd"),
      ("alice", "..", "123abcd"),
      ("alice", "repo", "main"),
    ] {
    reject(
      @protocol.GitHubRequest::CommitGet({ owner, repo, sha, page: 1, }).encode(),
    )
  }
  for body in ["", "   ", "a".repeat(65537), "中".repeat(22000)] {
    reject(
      @protocol.GitHubRequest::IssueCommentCreate({
        owner: "alice",
        repo: "repo",
        number: "1",
        body,
      }).encode(),
    )
  }
  for position in [0, -1] {
    reject(
      @protocol.GitHubRequest::CommitCommentCreate({
        owner: "alice",
        repo: "repo",
        sha: "123abcd",
        path: "a",
        position,
        body: "x",
      }).encode(),
    )
  }
  assert_false(@protocol.valid_attempt_id("short"))
  assert_true(@protocol.valid_attempt_id("attempt-0000000000"))
}

///|
test "source decoding validates base64 and byte length" {
  let source : @protocol.ApiSource = {
    base64: "aGk=",
    size: 2,
    content_type: "text/plain",
  }
  assert_eq(source.decode(), b"hi")
  for source in [{ ..source, size: 3, }, { ..source, base64: "!bad", }] {
    try source.decode() catch {
      _ => ()
    } noraise {
      _ => fail("Accepted invalid source")
    }
  }
}

///|
test "Viewed requests validate and roundtrip three states with snapshots" {
  let read : @protocol.GitHubRequest = PullViewedGet({
    owner: "alice",
    repo: "repo",
    number: "42",
  })
  let args : @protocol.PullFileViewedSet = {
    owner: "alice",
    repo: "repo",
    number: "42",
    path: "new/目录.mbt",
    viewed: true,
    base_sha: "123abcd",
    head_sha: "abcdef0",
  }
  let write : @protocol.GitHubRequest = PullFileViewedSet(args)
  assert_true(@protocol.decode_request(read.encode()) == read)
  assert_false(read.is_write())
  assert_true(@protocol.decode_request(write.encode()) == write)
  assert_true(write.is_write())
  roundtrip(
    @protocol.GitHubRequest::PullFileViewedSet({ ..args, viewed: false, }),
  )
  for state in [@protocol.FileViewedState::Viewed, Unviewed, Dismissed] {
    roundtrip(
      @protocol.RpcValue::PullViewed({
        base_sha: args.base_sha,
        head_sha: args.head_sha,
        files: [{ path: args.path, state, }],
      }),
    )
    roundtrip(
      @protocol.RpcValue::FileViewed({
        base_sha: args.base_sha,
        head_sha: args.head_sha,
        file: { path: args.path, state, },
      }),
    )
  }
  for
    bad in [
      @protocol.GitHubRequest::PullFileViewedSet({ ..args, path: "../bad", }),
      PullFileViewedSet({ ..args, base_sha: "latest", }),
      PullFileViewedSet({ ..args, head_sha: "HEAD", }),
      PullViewedGet({ owner: "alice", repo: "repo", number: "2147483648", }),
    ] {
    let rejected = try {
      bad.validate()
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
