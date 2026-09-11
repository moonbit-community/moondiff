///|
test "repository filenames roundtrip unchanged through source comments and Viewed" {
  for
    path in [
      "normal.mbt",
      "src/back\\slash.mbt",
      "src/line\nfeed.mbt",
      "src/tab\tname.mbt",
      "src/del\u007fname.mbt",
      "目录/🐇 space %?#.mbt",
      " leading and trailing ",
      "\\literal",
      "a".repeat(4096),
    ] {
    assert_true(@protocol.valid_repository_path(path))
    let requests : Array[@protocol.GitHubRequest] = [
      ContentGet({ owner: "alice", repo: "repo", path, revision: "123abcd", }),
      ReviewCommentCreate({
        owner: "alice",
        repo: "repo",
        number: "1",
        commit_id: "123abcd",
        path,
        line: 1,
        side: Right,
        body: "comment",
      }),
      CommitCommentCreate({
        owner: "alice",
        repo: "repo",
        sha: "123abcd",
        path,
        position: 1,
        body: "comment",
      }),
      PullFileViewedSet({
        owner: "alice",
        repo: "repo",
        number: "1",
        path,
        viewed: true,
        base_sha: "123abcd",
        head_sha: "abcdef0",
      }),
    ]
    for request in requests {
      assert_true(
        @protocol.decode_request(@json.parse(request.encode().stringify())) ==
        request,
      )
    }
    let result : @protocol.RpcValue = PullViewed({
      base_sha: "123abcd",
      head_sha: "abcdef0",
      files: [{ path, state: Viewed, }],
    })
    let decoded : @protocol.RpcValue = @protocol.decode(
      @json.parse(result.to_json().stringify()),
    )
    assert_true(decoded == result)
  }
}

///|
test "repository and static path validation keep separate boundaries" {
  for path in ["a\\b", "a\nb", "a\tb", "a\u007fb"] {
    assert_true(@protocol.valid_repository_path(path))
    assert_false(@protocol.valid_path(path))
  }
  for
    path in [
      "",
      "/absolute",
      "//host/file",
      ".",
      "..",
      "a/",
      "a//b",
      "a/./b",
      "a/../b",
      "a\u0000b",
      "a".repeat(4097),
    ] {
    assert_false(@protocol.valid_repository_path(path))
    for
      request in [
        @protocol.GitHubRequest::ContentGet({
          owner: "alice",
          repo: "repo",
          path,
          revision: "123abcd",
        }),
        ReviewCommentCreate({
          owner: "alice",
          repo: "repo",
          number: "1",
          path,
          commit_id: "123abcd",
          line: 1,
          side: Right,
          body: "comment",
        }),
        CommitCommentCreate({
          owner: "alice",
          repo: "repo",
          sha: "123abcd",
          path,
          position: 1,
          body: "comment",
        }),
        PullFileViewedSet({
          owner: "alice",
          repo: "repo",
          number: "1",
          path,
          viewed: true,
          base_sha: "123abcd",
          head_sha: "abcdef0",
        }),
      ] {
      try @protocol.decode_request(request.encode()) catch {
        @protocol.ProtocolError(code, _) => assert_eq(code, "invalid_path")
        error => raise error
      } noraise {
        _ => fail("accepted invalid repository path")
      }
    }
  }
}
