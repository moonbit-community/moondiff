///|
async fn cancelled(task : @async.Task[(@http.Response, Bytes)]) -> Unit {
  try task.wait() catch {
    @async.WaitedTaskAlreadyCancelled => ()
    error => raise error
  } noraise {
    _ => fail("expected cancellation")
  }
}

///|
async test "queue and body cancellation release capacity and discard partial responses" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let entered = @async.Semaphore(1, initial_value=0)
      let release = @async.Semaphore(1, initial_value=0)
      let paths : Array[String] = []
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(allow_failure=true, (request, _, conn) => {
          paths.push(request.path)
          conn.send_response(200, "OK", extra_headers={ "Content-Length": "2" })
          if request.path == "/blocked" {
            conn..write(b"o").flush()
            entered.release()
            release.acquire()
            conn.write(b"k")
          } else {
            conn.write(b"ok")
          }
          conn.end_response()
        })
      })
      let pool = Pool("http://127.0.0.1:\{server.addr.port()}", 1)
      defer pool.close()
      let reading = group.spawn(() => {
        pool.request("/blocked", Get, {}, None, 16)
      })
      entered.acquire()
      assert_eq(pool.connections.length(), 1)
      assert_true(
        @async.with_timeout_opt(5, () => {
          pool.request("/queued", Get, {}, None, 16)
        })
        is None,
      )
      assert_eq(paths, ["/blocked"])
      reading.cancel()
      cancelled(reading)
      assert_eq(pool.connections.length(), 0)
      let (_, bytes) = pool.request("/after", Get, {}, None, 16)
      assert_eq(bytes, b"ok")
      assert_eq(paths, ["/blocked", "/after"])
      assert_eq(pool.idle.length(), 1)
      pool.close()
      assert_eq(pool.connections.length(), 0)
      assert_eq(pool.idle.length(), 0)
      try pool.request("/closed", Get, {}, None, 16) catch {
        @io.ReaderClosed => ()
        error => raise error
      } noraise {
        _ => fail("closed pool accepted a request")
      }
    })
  })
}

///|
async test "idle expiry on borrow and return, response limits and failures preserve capacity" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let peers : Array[Int32] = []
      let entered = @async.Semaphore(1, initial_value=0)
      let release = @async.Semaphore(1, initial_value=0)
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(allow_failure=true, (request, _, conn) => {
          peers.push(conn.client_addr().port())
          if request.path == "/return" {
            entered.release()
            release.acquire()
          }
          conn.send_response(200, "OK", extra_headers={ "Content-Length": "2" })
          conn..write(b"ok").end_response()
        })
      })
      let pool = Pool("http://127.0.0.1:\{server.addr.port()}", 2)
      defer pool.close()
      ignore(pool.request("/one", Get, {}, None, 16))
      ignore(pool.request("/two", Get, {}, None, 16))
      assert_eq(peers[0], peers[1])
      pool.idle[0].idle_since = @async.now() - 15001
      ignore(pool.request("/expired", Get, {}, None, 16))
      assert_eq(pool.generation, 2L)
      let held = group.spawn(() => pool.request("/return", Get, {}, None, 16))
      entered.acquire()
      ignore(pool.request("/idle", Get, {}, None, 16))
      assert_eq(pool.connections.length(), 2)
      pool.idle[0].idle_since = @async.now() - 15001
      release.release()
      ignore(held.wait())
      assert_eq(pool.connections.length(), 1)
      try pool.request("/large", Get, {}, None, 1) catch {
        @common.RpcError(413, "response_too_large", _) => ()
        error => raise error
      } noraise {
        _ => fail("response limit was ignored")
      }
      assert_eq(pool.connections.length(), 0)
      ignore(pool.request("/recovered", Get, {}, None, 16))
      assert_eq(pool.connections.length(), 1)
    })
  })
}

///|
async test "recovery excludes timeout and non-disconnect OS failures" {
  assert_true(disconnected(@io.ReaderClosed))
  assert_false(disconnected(@os_error.OSError(1, context="read")))
  try @async.with_timeout(1, () => @async.sleep(1000)) catch {
    error => assert_false(disconnected(error))
  } noraise {
    _ => fail("expected timeout")
  }
}

///|
async test "HEAD recovers once on a reused connection and no write method is replayed" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let counts : Map[@http.RequestMethod, Int32] = Map([])
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(allow_failure=true, (request, _, conn) => {
          if request.path == "/drop" {
            let count = counts.get(request.meth).unwrap_or(0) + 1
            counts[request.meth] = count
            if request.meth != Head || count == 1 {
              conn.close()
              return
            }
          }
          if request.meth == Head {
            conn.send_response(200, "OK", extra_headers={
              "Content-Length": "1000",
              "Content-Encoding": "gzip",
            })
          } else {
            conn.send_response(200, "OK", extra_headers={
              "Content-Length": "0",
            })
          }
          conn.end_response()
        })
      })
      let pool = Pool("http://127.0.0.1:\{server.addr.port()}", 1)
      defer pool.close()
      ignore(pool.request("/warm", Get, {}, None, 16))
      let (_, bytes) = pool.request("/drop", Head, {}, None, 16)
      assert_eq(bytes, b"")
      assert_eq(counts[Head], 2)
      assert_eq(pool.generation, 2L)
      ignore(pool.request("/warm", Get, {}, None, 16))
      assert_eq(pool.generation, 2L)
      let methods : Array[@http.RequestMethod] = [Post, Put, Patch, Delete]
      for meth in methods {
        ignore(pool.request("/warm", Get, {}, None, 16))
        let failed = try {
          ignore(pool.request("/drop", meth, {}, None, 16))
          false
        } catch {
          _ => true
        }
        assert_true(failed)
        assert_eq(counts[meth], 1)
        assert_eq(pool.connections.length(), 0)
      }
    })
  })
}
