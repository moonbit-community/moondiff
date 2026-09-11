///|
async test "Viewed FIFO survives holder cancellation and failed waits and cleans idle scopes" {
  let db = @sqlite3.Connection::open(":memory:")
  defer db.close()
  let app : App = {
    config: {
      listen: "",
      public_url: "",
      static_dir: "",
      database: "",
      key: b"",
      client_id: "",
      install_url: "",
      api_url: "",
      oauth_url: "",
      secure: false,
    },
    db,
    refreshes: {},
    devices: {},
    viewed_scopes: {},
  }
  let session : Session = {
    id: "session",
    csrf: "",
    expires: 0,
    epoch: 0,
    user: "1",
    login: "alice",
    tokens: "unused",
    access_expires: 0,
    refresh_expires: 0,
  }
  let p : @protocol.PullViewedGet = {
    owner: "Alice",
    repo: "Repo",
    number: "42",
  }
  let entered = @async.Mutex()
  entered.acquire()
  let release = @async.Mutex()
  release.acquire()
  let log : Array[Int] = []
  @async.with_task_group(group => {
    let mut released = false
    defer (if !released { release.release() })
    let writer = group.spawn(() => {
      app.with_viewed_scope(Some(session), p, () => {
        @async.protect_from_cancel(() => {
          entered.release()
          release.acquire()
          log.push(0)
        })
      })
    })
    entered.acquire()
    writer.cancel()
    try
      (
        @async.with_timeout(5, () => {
          app.with_viewed_scope(Some(session), p, () => {
            fail("a timed out waiter must not execute")
          })
        }) : Unit)
    catch {
      @async.TimeoutError => ()
      error => raise error
    } noraise {
      _ => fail("expected a queue timeout")
    }
    assert_eq(app.viewed_scopes.length(), 1)
    assert_eq(app.viewed_scopes["1:alice/repo:42"].users, 1)
    // Two waiters, including a separate session, must keep their arrival order.
    let first = group.spawn(() => {
      app.with_viewed_scope(Some(session), p, () => log.push(1))
    })
    @async.sleep(1)
    let second = group.spawn(() => {
      app.with_viewed_scope(Some({ ..session, id: "another", }), p, () => {
        log.push(2)
      })
    })
    @async.sleep(1)
    assert_eq(app.viewed_scopes["1:alice/repo:42"].users, 3)
    assert_eq(log.length(), 0)
    released = true
    release.release()
    first.wait()
    second.wait()
  })
  assert_eq(log, [0, 1, 2])
  assert_eq(app.viewed_scopes.length(), 0)
  try
    (
      app.with_viewed_scope(Some(session), p, () => {
        raise RpcError(502, "test_failure", "failed operation")
      }) : Unit)
  catch {
    RpcError(502, _, _) => ()
    error => raise error
  } noraise {
    _ => fail("expected an operation failure")
  }
  assert_eq(app.viewed_scopes.length(), 0)
  app.with_viewed_scope(Some(session), p, () => log.push(3))
  assert_eq(log, [0, 1, 2, 3])
  assert_eq(app.viewed_scopes.length(), 0)
}
