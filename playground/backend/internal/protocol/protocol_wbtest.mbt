///|
test "root deployment routes reject hashes and unsafe paths" {
  for
    path in [
      "/alice/repo/commit/123abcd", "/alice/repo/pull/42", "/alice/repo/pull/42/commits/abcdef0",
    ] {
    assert_true(change_path(path))
  }
  for
    path in [
      "#/alice/repo/pull/42", "/alice/repo/pull/0", "/alice/repo/pull/42/files",
      "/alice/repo/commit/abc", "/-alice/repo/pull/42",
    ] {
    assert_false(change_path(path))
  }
  for path in ["../file", "a//b", "/root", "a\\b", "a/./b", "a\u0000b"] {
    assert_false(valid_path(path))
  }
  assert_eq(
    decode_component(encode_component("目录/a b.mbt")),
    "目录/a b.mbt",
  )
  try decode_component("%0x") catch {
    _ => ()
  } noraise {
    _ => fail("accepted invalid encoding")
  }
}

///|
test "protocol keeps decimal comment ids and removes null fields recursively" {
  let value = @json.parse(
    "{\"id\":9007199254740993,\"in_reply_to_id\":123,\"path\":null,\"user\":{\"login\":\"alice\",\"avatar_url\":null}}",
  )
  json_inspect(comment_for_protocol(value), content={
    "id": "9007199254740993",
    "in_reply_to_id": "123",
    "user": { "login": "alice" },
  })
}

///|
test "typed GitHub decoding removes unmodeled fields and rejects malformed modeled values" {
  let value : @api.ApiIssueComment = decode_github(
    comment_for_protocol(
      @json.parse(
        "{\"id\":9007199254740993,\"body\":\"hello\",\"html_url\":\"url\",\"created_at\":\"today\",\"user\":{\"login\":\"alice\",\"id\":1},\"extra\":true}",
      ),
    ),
  )
  json_inspect(value, content={
    "id": "9007199254740993",
    "body": "hello",
    "html_url": "url",
    "created_at": "today",
    "user": { "login": "alice" },
  })
  for
    invalid in [
      Json::object({}),
      {
        "filename": "a",
        "status": "added",
        "additions": 1.5,
        "deletions": 0,
        "changes": 1,
      },
      {
        "filename": "a",
        "status": "added",
        "additions": 4294967297.0,
        "deletions": 0,
        "changes": 1,
      },
    ] {
    try {
      let _ : @api.ApiFile = decode_github(invalid)
    } catch {
      RpcError(502, "invalid_github_response", _) => ()
      error => raise error
    } noraise {
      _ => fail("Accepted invalid upstream response")
    }
  }
}

///|
test "malformed upstream comments retain the upstream error category" {
  for
    value in [
      Json::null(),
      [],
      "invalid",
      {
        "id": "9223372036854775808",
        "body": "x",
        "html_url": "url",
        "created_at": "today",
      },
    ] {
    try {
      let _ : @api.ApiIssueComment = decode_github(comment_for_protocol(value))
    } catch {
      RpcError(502, "invalid_github_response", _) => ()
      error => raise error
    } noraise {
      _ => fail("Accepted invalid upstream comment")
    }
  }
}
