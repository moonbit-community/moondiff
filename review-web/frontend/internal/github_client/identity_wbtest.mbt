///|
fn TestCall::identity_failure(self : TestCall) -> Unit {
  let response : @protocol.Response[@protocol.ApiAuthStatus] = Failure(error={
    status: 503,
    code: "identity_unavailable",
    message: "Identity check unavailable",
  })
  (self.receive)(Ok((503, ToJson::to_json(response).stringify())))
}

///|
test "identity failure settles public and private snapshots completed before or after it" {
  for authenticated in [false, true] {
    for failure_first in [false, true] {
      for snapshot_failed in [false, true] {
        let (client, n) = harness()
        let status = if authenticated {
          status_fixture(phase=Completed)
        } else {
          anonymous_status_fixture()
        }
        client.adopt_status(status, false)
        let results : Array[Result[SnapshotResult, Error]] = []
        let task = client.new_snapshot_task(snapshot_args(), false, "", [
          { generation: 1, done: r => results.push(r), },
        ])
        let snapshot : Result[PullSnapshot, Error] = if snapshot_failed {
          Err(snapshot_error("Snapshot read failed"))
        } else {
          Ok({
            metadata: snapshot_pull(),
            comparison: snapshot_comparison(),
            files: [],
            signature: "fixture",
          })
        }
        client.status(_ => ())
        if failure_first {
          n.last().identity_failure()
        }
        client.finish_snapshot(task, snapshot)
        if !failure_first {
          assert_true(results.is_empty())
          n.last().identity_failure()
        }
        assert_false(client.workspace.checking)
        assert_true(client.workspace.deferred.is_empty())
        assert_eq(results.length(), 1)
        if authenticated {
          assert_true(
            results[0] is Err(HttpRequestError(code="identity_unavailable", ..)),
          )
        } else if snapshot_failed {
          assert_true(
            results[0]
            is Err(HttpRequestError(code="pull_snapshot_changed", ..)),
          )
        } else {
          assert_true(results[0] is Ok({ confirmed: true, .. }))
        }
        client.adopt_status(status, false)
        assert_eq(results.length(), 1)
      }
    }
  }
}

///|
test "failed identity rejects deferred writes once and never replays them after recovery" {
  let (client, n) = snapshot_harness()
  client.status(_ => ())
  let status = n.last()
  let results : Array[Result[@protocol.RpcValue, Error]] = []
  let request : @protocol.GitHubRequest = IssueCommentCreate({
    owner: "upstream",
    repo: "repo",
    number: "1",
    body: "Do not replay",
  })
  client.rpc(request, 1, value => value, r => results.push(r))
  assert_eq(n.calls.length(), 1)
  status.identity_failure()
  assert_true(
    results is [Err(HttpRequestError(code="identity_unavailable", ..))],
  )
  assert_true(client.workspace.deferred.is_empty())
  // A new write also needs a successful identity check before it can be sent.
  client.rpc(request, 1, value => value, r => results.push(r))
  assert_eq(results.length(), 2)
  assert_true(
    results[1] is Err(HttpRequestError(code="identity_unavailable", ..)),
  )
  assert_eq(n.calls.length(), 1)
  client.status(_ => ())
  n.last().reply(status_fixture(phase=Completed, csrf="recovered-csrf"))
  assert_eq(n.calls.length(), 2)
  assert_eq(results.length(), 2)
  assert_true(client.workspace.deferred.is_empty())
  client.rpc(request, 1, value => value, r => results.push(r))
  assert_eq(n.calls.length(), 3)
  assert_eq(n.last().csrf, "recovered-csrf")
  assert_true(n.last().request() is IssueCommentCreate(_))
}

///|
test "obsolete status responses cannot settle the newer identity check" {
  for failed in [false, true] {
    let (client, n) = snapshot_harness()
    let older : Array[Result[@protocol.ApiAuthStatus, Error]] = []
    client.status(r => older.push(r))
    let previous = n.last()
    client.status(_ => ())
    let current = n.last()
    let writes : Array[Result[@protocol.RpcValue, Error]] = []
    client.rpc(
      IssueCommentCreate({
        owner: "upstream",
        repo: "repo",
        number: "1",
        body: "Wait",
      }),
      1,
      value => value,
      r => writes.push(r),
    )
    if failed {
      previous.identity_failure()
    } else {
      previous.reply(status_fixture(phase=Completed))
    }
    assert_true(older is [Err(Cancelled)])
    assert_true(client.workspace.checking)
    assert_eq(client.workspace.deferred.length(), 1)
    assert_true(writes.is_empty())
    current.identity_failure()
    assert_false(client.workspace.checking)
    assert_true(
      writes is [Err(HttpRequestError(code="identity_unavailable", ..))],
    )
  }
}

///|
test "cancelled identity requests leave waiting work for the next status query" {
  let (client, n) = snapshot_harness()
  let results : Array[Result[@protocol.ApiAuthStatus, Error]] = []
  client.status(r => results.push(r))
  let previous = n.last()
  client.invalidate_auth(false)
  client.status(_ => ())
  assert_true(results is [Err(Cancelled)])
  previous.identity_failure()
  assert_true(client.workspace.checking)
  n.last().reply(status_fixture(phase=Completed))
  assert_false(client.workspace.checking)
}

///|
test "identity failures stop active and paused prefetch without starting another request" {
  for paused in [false, true] {
    let (client, n) = snapshot_harness()
    if paused {
      client.status(_ => ())
    }
    client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
    n.tick()
    let background = n.last()
    if !paused {
      client.status(_ => ())
    }
    n.last().identity_failure()
    assert_false(client.workspace.checking)
    assert_false(client.workspace.home)
    assert_true(client.workspace.tasks.is_empty())
    assert_eq(n.timer_count(), 0)
    if !paused {
      assert_true(background.aborted)
    }
    assert_eq(n.calls.length(), if paused { 1 } else { 2 })
  }
}

///|
test "failed deferred snapshots and writes still honor generation and workspace boundaries" {
  for boundary in [false, true] {
    let (client, n) = snapshot_harness()
    let results : Array[Result[SnapshotResult, Error]] = []
    let task = client.new_snapshot_task(snapshot_args(), false, "", [
      { generation: 1, done: r => results.push(r), },
    ])
    client.status(_ => ())
    client.finish_snapshot(task, Err(snapshot_error("Read failed")))
    let writes : Array[Result[@protocol.RpcValue, Error]] = []
    client.rpc(
      IssueCommentCreate({
        owner: "upstream",
        repo: "repo",
        number: "1",
        body: "Old generation",
      }),
      1,
      value => value,
      r => writes.push(r),
    )
    if boundary {
      client.clear_workspace()
    } else {
      client.cancel_before(2)
    }
    n.last().identity_failure()
    assert_true(results.is_empty())
    assert_true(writes.is_empty())
    assert_true(client.workspace.deferred.is_empty())
  }
}
