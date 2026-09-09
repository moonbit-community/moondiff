///|
priv struct TestCall {
  path : String
  meth : String
  csrf : String
  body : String
  receive : (Result[(Int, String), String]) -> Unit
  mut aborted : Bool
}

///|
priv struct TestTimer {
  ms : Int
  run : () -> Unit
  mut cleared : Bool
}

///|
priv struct Network {
  calls : Array[TestCall]
  timers : Array[TestTimer]
}

///|
fn harness() -> (Client, Network) {
  let network : Network = { calls: [], timers: [], }
  let transport : Transport = {
    send: (path, meth, csrf, body, receive) => {
      let call : TestCall = { path, meth, csrf, body, receive, aborted: false, }
      network.calls.push(call)
      () => call.aborted = true
    },
    delay: (ms, run) => {
      let timer : TestTimer = { ms, run, cleared: false, }
      network.timers.push(timer)
      () => timer.cleared = true
    },
  }
  (Client::new(transport), network)
}

///|
fn[T : ToJson] TestCall::reply(self : TestCall, value : T) -> Unit {
  let response : @protocol.Response[T] = Success(value~)
  (self.receive)(Ok((200, response.to_json().stringify())))
}

///|
fn Network::last(self : Network) -> TestCall {
  self.calls[self.calls.length() - 1]
}

///|
fn Network::tick(self : Network) -> Unit {
  for timer in self.timers {
    if !timer.cleared {
      timer.cleared = true
      (timer.run)()
      return
    }
  }
  abort("Expected a timer")
}

///|
fn Network::timer_count(self : Network) -> Int {
  self.timers.filter(t => !t.cleared).length()
}

///|
fn status_fixture(
  id? : String,
  phase? : @protocol.DevicePhase = Pending,
  csrf? : String = "csrf-123",
) -> @protocol.ApiAuthStatus {
  {
    authenticated: phase is Completed,
    csrf_token: csrf,
    login: None,
    user_id: if phase is Completed {
      Some("1")
    } else {
      None
    },
    install_url: None,
    device_flow: id.map(id => {
      id,
      phase,
      user_code: "CODE",
      verification_uri: "https://github.com/login/device",
      expires_at: 2000000000,
      retry_after: 5,
      message: "",
    }),
  }
}

///|
fn device_fixture(
  request_id : String,
  id? : String,
  phase? : @protocol.DevicePhase = Pending,
) -> @protocol.DeviceResponse {
  { request_id, status: status_fixture(id?, phase~), }
}

///|
fn seed(
  client : Client,
  network : Network,
  id? : String = "attempt-0000000000",
) -> Unit {
  client.status(_ => ())
  network.last().reply(status_fixture(id~))
}

///|
test "transport sends v2 JSON and CSRF; errors and malformed responses stay actionable" {
  let (client, n) = harness()
  seed(client, n)
  assert_eq(n.calls[0].path, "/api/auth/status")
  assert_eq(n.calls[0].meth, "GET")
  let request : @protocol.GitHubRequest = IssueCommentDelete({
    owner: "alice",
    repo: "repo",
    comment_id: 9007199254740993L,
  })
  let results : Array[Result[@protocol.RpcValue, Error]] = []
  client.send(
    "/api/rpc",
    request.encode().stringify(),
    r => results.push(r),
    generation=1,
  )
  let call = n.last()
  assert_eq(call.meth, "POST")
  assert_eq(call.csrf, "csrf-123")
  assert_true(
    try! (@protocol.decode_request(try! @json.parse(call.body)) == request),
  )
  let denied : @protocol.Response[@protocol.RpcValue] = Failure(error={
    status: 403,
    code: "permission_denied",
    message: "No access",
  })
  (call.receive)(Ok((403, denied.to_json().stringify())))
  assert_true(
    results[0]
    is Err(
      HttpRequestError(status=403, code="permission_denied", detail="No access")
    ),
  )
  client.send("/api/rpc", request.encode().stringify(), r => results.push(r))
  (n.last().receive)(Ok((200, "{}")))
  assert_true(
    results[1] is Err(HttpRequestError(code="invalid_server_response", ..)),
  )
  client.send("/api/rpc", request.encode().stringify(), r => results.push(r))
  (n.last().receive)(Err("offline"))
  assert_true(
    results[2]
    is Err(HttpRequestError(status=0, code="network_error", detail="offline")),
  )
  assert_eq(client.pending.length(), 0)
}

///|
test "malformed responses preserve HTTP status with a fixed error message" {
  for http_status in [200, 502, 503, 504] {
    for
      text in [
        "<html><body>Proxy unavailable</body></html>", "", "{invalid json", "{}",
        "{\"$tag\":\"Success\",\"value\":null,\"unexpected\":true}",
      ] {
      let (client, n) = harness()
      let results : Array[Result[Unit, Error]] = []
      client.send("/api/rpc", "{}", r => results.push(r))
      (n.last().receive)(Ok((http_status, text)))
      assert_eq(results.length(), 1)
      guard results[0] is Err(HttpRequestError(status~, code~, detail~)) else {
        fail("Expected an HTTP error for a malformed response")
      }
      assert_eq(status, http_status)
      assert_eq(code, "invalid_server_response")
      assert_eq(detail, "The server returned an invalid response.")
      assert_eq(client.pending.length(), 0)
    }
  }
}

///|
test "success responses with non-2xx HTTP status are rejected with that status" {
  let response : @protocol.Response[Unit] = Success(value=())
  for http_status in [199, 300, 400, 502, 503, 504] {
    let (client, n) = harness()
    let results : Array[Result[Unit, Error]] = []
    client.send("/api/rpc", "{}", r => results.push(r))
    (n.last().receive)(Ok((http_status, response.to_json().stringify())))
    guard results[0] is Err(HttpRequestError(status~, code~, detail~)) else {
      fail("Expected an HTTP error for a non-2xx success response")
    }
    assert_eq(status, http_status)
    assert_eq(code, "invalid_server_response")
    assert_eq(detail, "Invalid HTTP status.")
  }
}

///|
test "valid failure responses retain the server status code and message" {
  let response : @protocol.Response[Unit] = Failure(error={
    status: 403,
    code: "permission_denied",
    message: "No access to this repository.",
  })
  for http_status in [200, 403, 503] {
    let (client, n) = harness()
    let results : Array[Result[Unit, Error]] = []
    client.send("/api/rpc", "{}", r => results.push(r))
    (n.last().receive)(Ok((http_status, response.to_json().stringify())))
    assert_true(
      results[0]
      is Err(
        HttpRequestError(
          status=403,
          code="permission_denied",
          detail="No access to this repository."
        )
      ),
    )
  }
}

///|
test "navigation cancels old generations and leaves authorization and polling alive" {
  let (client, n) = harness()
  let result : Array[Result[Unit, Error]] = []
  client.send("/api/rpc", "{}", r => result.push(r), generation=2)
  let old = n.last()
  seed(client, n)
  client.device(Poll, "attempt-0000000000", 10, _ => ())
  client.cancel_before(3)
  assert_true(old.aborted)
  assert_true(result[0] is Err(Cancelled))
  assert_eq(n.timer_count(), 1)
  old.reply(())
  (old.receive)(Err("late failure"))
  assert_eq(result.length(), 1)
  let count = n.calls.length()
  client.send("/api/rpc", "{}", r => result.push(r), generation=1)
  assert_eq(n.calls.length(), count)
  assert_true(result[1] is Err(Cancelled))
  client.dispose()
  assert_eq(n.timer_count(), 0)
  assert_eq(client.pending.length(), 0)
}

///|
test "newer session reads and logout prevent late auth or CSRF restoration" {
  let (client, n) = harness()
  let results : Array[Result[@protocol.ApiAuthStatus, Error]] = []
  client.status(r => results.push(r))
  let old = n.last()
  client.status(r => results.push(r))
  n.last().reply(status_fixture(csrf="current"))
  old.reply(status_fixture(phase=Completed, csrf="stale"))
  assert_true(results[1] is Err(Cancelled))
  assert_eq(client.csrf, "current")
  client.status(r => results.push(r))
  let old = n.last()
  client.logout(r => results.push(r))
  assert_eq(n.last().path, "/api/auth/logout")
  n.last().reply(())
  assert_eq(n.last().path, "/api/auth/status")
  n.last().reply(status_fixture(csrf="fresh"))
  old.reply(status_fixture(phase=Completed, csrf="stale"))
  assert_eq(client.csrf, "fresh")
  assert_true(old.aborted)
}

///|
test "device start echoes attempt and one delayed poll serves concurrent waiters" {
  let (client, n) = harness()
  let results : Array[Result[@protocol.DeviceResponse, Error]] = []
  let id = "attempt-0000000000"
  client.device(Start, id, 0, r => results.push(r))
  n.last().reply(status_fixture())
  assert_eq(n.last().path, "/api/auth/device/start")
  assert_eq(n.last().body, "{\"attempt_id\":\"attempt-0000000000\"}")
  n.last().reply(device_fixture(id, id~))
  for delay in [11, 0] {
    client.device(Poll, id, delay, r => results.push(r))
  }
  assert_eq(n.timer_count(), 1)
  assert_eq(n.timers[0].ms, 11000)
  assert_eq(n.calls.length(), 2)
  n.tick()
  client.device(Poll, id, 0, r => results.push(r))
  assert_eq(n.calls.length(), 3)
  assert_eq(n.last().body, "{\"authorization_id\":\"attempt-0000000000\"}")
  n.last().reply(device_fixture(id, id~, phase=Completed))
  assert_eq(results.length(), 4)
  assert_true(
    results[1:].all(r => r is Ok({ status: { user_id: Some("1"), .. }, .. })),
  )
  assert_eq(n.timer_count(), 0)
  assert_true(client.poll_task is None)
}

///|
test "cancel logout and page departure reject waiting and in-flight polls exactly once" {
  for action in ["cancel", "logout", "pagehide"] {
    for in_flight in [false, true] {
      for failed in [false, true] {
        let (client, n) = harness()
        let id = "attempt-0000000000"
        seed(client, n)
        let results : Array[Result[@protocol.DeviceResponse, Error]] = []
        client.device(Poll, id, 5, r => results.push(r))
        if in_flight {
          n.tick()
        }
        let old = n.last()
        match action {
          "cancel" => client.device(Cancel, id, 0, _ => ())
          "logout" => client.logout(_ => ())
          _ => client.dispose()
        }
        assert_eq(n.timer_count(), 0)
        assert_true(results[0] is Err(Cancelled))
        if failed {
          (old.receive)(Err("late network error"))
        } else {
          old.reply(device_fixture(id, id~, phase=Completed))
        }
        assert_eq(results.length(), 1)
        assert_eq(client.csrf, "csrf-123")
      }
    }
  }
}

///|
test "poll completion invalidates an earlier session read" {
  let (client, n) = harness()
  let id = "attempt-0000000000"
  seed(client, n)
  let results : Array[Result[@protocol.ApiAuthStatus, Error]] = []
  client.status(r => results.push(r))
  let old = n.last()
  client.device(Poll, id, 0, _ => ())
  n.tick()
  n.last().reply(device_fixture(id, id~, phase=Completed))
  old.reply(status_fixture(id~))
  assert_true(results[0] is Err(Cancelled))
  assert_true(client.device_id is None)
}

///|
test "mismatched device identifiers fail without adopting state" {
  for mismatched_request in [true, false] {
    let (client, n) = harness()
    let id = "attempt-0000000000"
    seed(client, n)
    let results : Array[Result[@protocol.DeviceResponse, Error]] = []
    client.device(Poll, id, 0, r => results.push(r))
    n.tick()
    n
    .last()
    .reply(
      device_fixture(
        if mismatched_request {
          "wrong"
        } else {
          id
        },
        id=if mismatched_request { id } else { "wrong" },
      ),
    )
    assert_true(
      results[0] is Err(HttpRequestError(code="invalid_server_response", ..)),
    )
    assert_eq(client.device_id, Some(id))
  }
}

///|
test "failed session reads and lost start responses retain attempt until canonical recovery" {
  for lost_start in [false, true] {
    let (client, n) = harness()
    let id = "attempt-0000000000"
    let canonical = "canonical-authorization"
    let results : Array[Result[@protocol.DeviceResponse, Error]] = []
    client.device(Start, id, 0, r => results.push(r))
    if lost_start {
      n.last().reply(status_fixture())
    }
    (n.last().receive)(Err("offline"))
    for delay in [10, 20] {
      client.device(Retry, id, delay, r => results.push(r))
      assert_eq(n.timer_count(), 1)
      assert_eq(n.timers[n.timers.length() - 1].ms, delay * 1000)
      n.tick()
      (n.last().receive)(Err("offline"))
    }
    client.device(Retry, id, 40, r => results.push(r))
    client.device(Retry, id, 0, r => results.push(r))
    n.tick()
    n.last().reply(status_fixture(id=canonical, csrf="fresh"))
    assert_eq(n.last().path, "/api/auth/device/start")
    assert_eq(n.last().csrf, "fresh")
    assert_eq(n.last().body, "{\"attempt_id\":\"attempt-0000000000\"}")
    n.last().reply(device_fixture(id, id=canonical))
    assert_eq(client.device_id, Some(canonical))
    assert_true(client.pending_start_id is None)
    assert_eq(results.length(), 5)
    assert_true(
      results[3]
      is Ok(
        {
          status: {
            device_flow: Some({ id: "canonical-authorization", .. }),
            ..
          },
          ..
        }
      ),
    )
    client.device(Retry, id, 0, r => results.push(r))
    assert_true(results[5] is Err(Cancelled))
    client.device(Poll, canonical, 5, _ => ())
    n.tick()
    assert_eq(
      n.last().body,
      "{\"authorization_id\":\"canonical-authorization\"}",
    )
  }
}

///|
test "restored starting status retries the original attempt" {
  let (client, n) = harness()
  let id = "attempt-0000000000"
  client.status(_ => ())
  n.last().reply(status_fixture(id~, phase=Starting))
  client.device(Retry, id, 5, _ => ())
  n.tick()
  n.last().reply(status_fixture(id~, phase=Starting))
  assert_eq(n.last().path, "/api/auth/device/start")
  assert_eq(n.last().body, "{\"attempt_id\":\"attempt-0000000000\"}")
}

///|
test "cancel logout and page departure discard late start success and failure at every stage" {
  for action in ["cancel", "logout", "pagehide"] {
    for stage in ["initial-session", "timer", "retry-session", "retry-start"] {
      for failed in [false, true] {
        let (client, n) = harness()
        let id = "attempt-0000000000"
        let results : Array[Result[@protocol.DeviceResponse, Error]] = []
        client.device(Start, id, 0, r => results.push(r))
        if stage != "initial-session" {
          (n.last().receive)(Err("offline"))
          client.device(Retry, id, 10, r => results.push(r))
          if stage != "timer" {
            n.tick()
          }
          if stage == "retry-start" {
            n.last().reply(status_fixture())
          }
        }
        let old = n.last()
        match action {
          "cancel" => client.device(Cancel, id, 0, _ => ())
          "logout" => client.logout(_ => ())
          _ => client.dispose()
        }
        assert_eq(n.timer_count(), 0)
        assert_true(results[results.length() - 1] is Err(Cancelled))
        let count = results.length()
        client.device(Start, "next-attempt-00000", 0, _ => ())
        n.last().reply(status_fixture())
        n
        .last()
        .reply(device_fixture("next-attempt-00000", id="next-attempt-00000"))
        if failed {
          (old.receive)(Err("late failure"))
        } else if stage == "retry-start" {
          old.reply(device_fixture(id, id~))
        } else {
          old.reply(status_fixture(id~))
        }
        assert_eq(results.length(), count)
        assert_eq(client.device_id, Some("next-attempt-00000"))
        client.device(Retry, id, 5, r => results.push(r))
        assert_true(results[count] is Err(Cancelled))
        assert_eq(n.timer_count(), 0)
      }
    }
  }
}

///|
test "RPC response kind mismatch is invalid_server_response and invalid requests do not reach transport" {
  let (client, n) = harness()
  let results : Array[Result[@protocol.ApiCompare, Error]] = []
  let request : @protocol.GitHubRequest = CompareGet({
    owner: "alice",
    repo: "repo",
    base: "123abcd",
    head: "abcdef0",
  })
  let select = (value : @protocol.RpcValue) => {
    guard value is Compare(data) else {
      raise invalid_response("Wrong result kind")
    }
    data
  }
  client.rpc(request, 1, select, r => results.push(r))
  n.last().reply(@protocol.RpcValue::Deleted({ deleted: true, }))
  assert_true(
    results[0] is Err(HttpRequestError(code="invalid_server_response", ..)),
  )
  client.rpc(request, 1, select, r => results.push(r))
  n
  .last()
  .reply(
    @protocol.RpcValue::Compare({ merge_base_commit: { sha: "123abcd", }, }),
  )
  assert_true(results[1] is Ok({ merge_base_commit: { sha: "123abcd", }, }))
  client.rpc(
    CompareGet({
      owner: "../alice",
      repo: "repo",
      base: "123abcd",
      head: "abcdef0",
    }),
    1,
    select,
    r => results.push(r),
  )
  assert_eq(n.calls.length(), 2)
  assert_true(results[2] is Err(_))
}
