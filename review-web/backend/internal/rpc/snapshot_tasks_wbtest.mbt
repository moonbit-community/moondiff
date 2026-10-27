///|
fn snapshot_result_fixture() -> @protocol.ApiPullSnapshotResult {
  MetadataOnly({
    title: "snapshot",
    body: None,
    html_url: "url",
    base: { sha: "a".repeat(40), repo: None, },
    head: { sha: "b".repeat(40), repo: None, },
    additions: 0,
    deletions: 0,
    changed_files: 301,
    commits: None,
  })
}

///|
async fn wait_for_snapshot_waiters(
  reads : Map[String, @storage.SnapshotRead],
  expected : Int32,
) -> Unit {
  for _ in 0..<10000 {
    if reads.get("pull") is Some(entry) && entry.waiters == expected {
      return
    }
    @async.pause()
  }
  fail("snapshot did not reach \{expected} waiters")
}

///|
async fn cancelled_snapshot(
  task : @async.Task[@protocol.ApiPullSnapshotResult],
) -> Unit {
  try task.wait() catch {
    @async.WaitedTaskAlreadyCancelled => ()
    error => raise error
  } noraise {
    _ => fail("expected cancellation")
  }
}

///|
async test "snapshot sharing survives one cancelled waiter and cleans successful and failed tasks" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let reads : Map[String, @storage.SnapshotRead] = Map([])
      let release = @async.Semaphore(1, initial_value=0)
      let mut runs = 0
      async fn read() -> @protocol.ApiPullSnapshotResult {
        runs += 1
        release.acquire()
        snapshot_result_fixture()
      }
      let first = group.spawn(() => with_snapshot_read(reads, "pull", 1, read))
      let second = group.spawn(() => with_snapshot_read(reads, "pull", 2, read))
      wait_for_snapshot_waiters(reads, 2)
      first.cancel()
      cancelled_snapshot(first)
      assert_eq(reads["pull"].waiters, 1)
      release.release()
      assert_true(second.wait() is MetadataOnly(_))
      assert_eq(runs, 1)
      assert_true(reads.is_empty())
      async fn failing_waiter(generation : Int64) -> String {
        try
          with_snapshot_read(reads, "pull", generation, () => {
            runs += 1
            release.acquire()
            raise @common.RpcError(502, "test_failure", "failed read")
          })
        catch {
          @common.RpcError(_, code, _) => code
          error => raise error
        } noraise {
          _ => "unexpected success"
        }
      }
      let failed_first = group.spawn(() => failing_waiter(3))
      let failed_second = group.spawn(() => failing_waiter(4))
      wait_for_snapshot_waiters(reads, 2)
      release.release()
      assert_eq(failed_first.wait(), "test_failure")
      assert_eq(failed_second.wait(), "test_failure")
      assert_true(reads.is_empty())
      assert_eq(runs, 2)
      ignore(
        with_snapshot_read(reads, "pull", 5, () => snapshot_result_fixture()),
      )
      assert_true(reads.is_empty())
    })
  })
}

///|
async test "all snapshot waiters cancelling remove registration immediately and cancel upstream work" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let reads : Map[String, @storage.SnapshotRead] = Map([])
      let entered = @async.Semaphore(1, initial_value=0)
      let cleaned = @async.Semaphore(1, initial_value=0)
      let mut runs = 0
      async fn read() -> @protocol.ApiPullSnapshotResult {
        runs += 1
        defer cleaned.release()
        entered.release()
        @async.sleep(60000)
        snapshot_result_fixture()
      }
      let first = group.spawn(() => with_snapshot_read(reads, "pull", 1, read))
      let second = group.spawn(() => with_snapshot_read(reads, "pull", 2, read))
      entered.acquire()
      wait_for_snapshot_waiters(reads, 2)
      first.cancel()
      second.cancel()
      cancelled_snapshot(first)
      cancelled_snapshot(second)
      assert_true(reads.is_empty())
      cleaned.acquire()
      assert_eq(runs, 1)
      ignore(
        with_snapshot_read(reads, "pull", 3, () => snapshot_result_fixture()),
      )
      assert_true(reads.is_empty())
    })
  })
}

///|
async test "an old snapshot generation cannot delete a replacement task" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let reads : Map[String, @storage.SnapshotRead] = Map([])
      let old_entered = @async.Semaphore(1, initial_value=0)
      let old_release = @async.Semaphore(1, initial_value=0)
      let old_cleaned = @async.Semaphore(1, initial_value=0)
      let old = group.spawn(() => {
        with_snapshot_read(reads, "pull", 1, () => {
          @async.protect_from_cancel(() => {
            old_entered.release()
            old_release.acquire()
            old_cleaned.release()
            snapshot_result_fixture()
          })
        })
      })
      old_entered.acquire()
      old.cancel()
      cancelled_snapshot(old)
      assert_true(reads.is_empty())
      let new_release = @async.Semaphore(1, initial_value=0)
      let replacement = group.spawn(() => {
        with_snapshot_read(reads, "pull", 2, () => {
          new_release.acquire()
          snapshot_result_fixture()
        })
      })
      wait_for_snapshot_waiters(reads, 1)
      old_release.release()
      old_cleaned.acquire()
      // Exercise the generation guard even if the old worker's task-group
      // cancellation cleanup has not yet been scheduled by the runtime.
      forget_snapshot_read(reads, "pull", 1)
      assert_eq(reads["pull"].generation, 2L)
      new_release.release()
      ignore(replacement.wait())
      assert_true(reads.is_empty())
    })
  })
}
