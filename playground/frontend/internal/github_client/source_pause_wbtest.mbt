///|
test "source rate limits drain queued waiters and preserve successful in-flight reads" {
  for status in [403, 429] {
    let (client, n) = snapshot_harness()
    let results : Array[(Int32, Result[@protocol.RpcValue, Error])] = []
    for i in 0..<40 {
      client.read(
        ContentGet({
          owner: "upstream",
          repo: "repo",
          path: "file\{i}.mbt",
          revision: "a".repeat(40),
        }),
        1,
        result => results.push((i, result)),
      )
    }
    assert_eq(n.calls.length(), 4)
    let failure : @protocol.Response[@protocol.RpcValue] = Failure(error={
      status,
      code: "rate_limit",
      message: "limited",
    })
    (n.calls[0].receive)(Ok((status, ToJson::to_json(failure).stringify())))
    assert_eq(results.length(), 37)
    assert_true(
      results.all(entry => entry.1 is Err(RateLimited(AuthenticatedRequests))),
    )
    for call in n.calls[1:] {
      call.reply(
        @protocol.RpcValue::Content({
          size: 3,
          base64: "b2xk",
          content_type: "text/plain",
        }),
      )
    }
    assert_eq(results.length(), 40)
    assert_eq(results.filter(entry => entry.1 is Ok(_)).length(), 3)
    assert_true(client.workspace.reads.is_empty())
    assert_true(client.workspace.source_pause == Some(AuthenticatedRequests))
    client.read(
      ContentGet({
        owner: "upstream",
        repo: "repo",
        path: "extra.mbt",
        revision: "a".repeat(40),
      }),
      2,
      result => results.push((40, result)),
      priority=true,
    )
    client.pump_sources()
    assert_eq(n.calls.length(), 4)
    assert_eq(n.timer_count(), 0)
  }
}

///|
test "late anonymous rate limit reports dispatch identity without pausing signed-in sources" {
  let (client, _) = snapshot_harness()
  let error = HttpRequestError(status=429, code="rate_limit", detail="limited")
  let result : Result[Int32, Error] = client.request_result(Err(error), false)
  assert_true(result is Err(RateLimited(AnonymousRequests)))
  assert_true(client.workspace.source_pause is None)
  let result : Result[Int32, Error] = client.request_result(Err(error), true)
  assert_true(result is Err(RateLimited(AuthenticatedRequests)))
  assert_true(client.workspace.source_pause == Some(AuthenticatedRequests))
}
