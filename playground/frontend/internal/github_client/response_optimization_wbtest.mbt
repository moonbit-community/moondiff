///|
fn drive_prefetch_fixture(n : Network, count : Int32) -> Unit {
  for _ in 0..<100 {
    guard n.calls
      .iter()
      .find_first(call => {
        !call.answered && !call.aborted && call.path == "/api/rpc"
      })
      is Some(call) else {
      return
    }
    match call.request() {
      PullGet(_) => call.reply(@protocol.RpcValue::Pull(snapshot_pull(count~)))
      CompareGet(_) =>
        call.reply(@protocol.RpcValue::Compare(snapshot_comparison()))
      PullFiles(args) =>
        call.reply(
          @protocol.RpcValue::Files(
            Array::makei(Int32::min(100, count - (args.page - 1) * 100), i => {
              snapshot_file(i + (args.page - 1) * 100)
            }),
          ),
        )
      ContentGet(_) =>
        call.reply(
          @protocol.RpcValue::Content({
            size: 3,
            base64: "b2xk",
            content_type: "text/plain",
          }),
        )
      _ => abort("unexpected prefetch stage")
    }
  }
  abort("prefetch failed to terminate")
}

///|
test "prefetch covers file boundaries through 300 and keeps only two full candidates" {
  for count in [100, 101, 112, 300, 301] {
    let (client, n) = snapshot_harness()
    client.prefetch_home(
      Array::makei(7, i => {
        pull: snapshot_args(number=(i + 1).to_string()),
        updated_at: "",
      }),
      0,
    )
    n.tick()
    drive_prefetch_fixture(n, count)
    let selected : Map[String, Bool] = Map([])
    for call in n.calls {
      if call.request() is PullGet(args) {
        selected[args.number] = true
      }
    }
    assert_eq(selected.length(), 5)
    assert_false(selected.contains("6"))
    let comparisons = n.calls.filter(call => call.request() is CompareGet(_))
    assert_eq(comparisons.length(), if count <= 300 { 2 } else { 0 })
    let pages = n.calls.filter(call => call.request() is PullFiles(_))
    assert_eq(
      pages.length(),
      if count <= 300 {
        2 * ((count + 99) / 100)
      } else {
        0
      },
    )
    if count <= 300 {
      let source = n.calls
        .search_by(call => call.request() is ContentGet(_))
        .unwrap()
      let second = n.calls
        .search_by(call => call.request() is PullGet({ number: "2", .. }))
        .unwrap()
      assert_true(source < second)
    }
    assert_true(client.workspace.background_owner is None)
    assert_true(client.workspace.tasks.is_empty())
  }
}

///|
test "unknown hints retain stale snapshots and metadata refresh never overwrites a complete version" {
  let (client, n) = snapshot_harness()
  client.load_snapshot(snapshot_args(), 1, _ => ())
  finish_fixture(n, snapshot_pull(), [])
  client.workspace.cache = client.workspace.cache.map(entry => {
    ..entry,
    created: 0,
  })
  let task = client.new_snapshot_task(snapshot_args(), true, "new hint", [])
  task.metadata_only = true
  client.build_snapshot(task, { ..snapshot_pull(), title: "Updated title", })
  assert_true(
    client.workspace.cached(
      pull_key(snapshot_args()),
      @browser.date_now(),
      hint="changed",
    )
    is Some(Snapshot(_)),
  )
  assert_true(
    client.workspace.cached(metadata_key(snapshot_args()), @browser.date_now())
    is Some(Metadata({ title: "Updated title", .. })),
  )
  let result = []
  client.load_snapshot(snapshot_args(), 2, value => result.push(value))
  assert_true(result is [Ok({ confirmed: false, .. })])
  assert_true(n.last().request() is PullGet(_))
  n.reply_metadata(snapshot_pull())
  assert_true(
    result is [Ok({ confirmed: false, .. }), Ok({ confirmed: true, .. })],
  )
}

///|
test "a cold aggregate completes with one snapshot RPC and no repeated browser phases" {
  let (client, n) = snapshot_harness()
  let result = []
  client.load_snapshot(snapshot_args(), 1, value => result.push(value))
  assert_true(n.last().request() is PullSnapshotGet(_))
  let pull = snapshot_pull(count=1)
  n
  .last()
  .reply(
    @protocol.RpcValue::PullSnapshot(
      Complete({
        metadata: pull,
        comparison: snapshot_comparison(),
        files: [snapshot_file(0)],
        signature: snapshot_signature(pull, snapshot_comparison()),
      }),
    ),
  )
  assert_eq(n.calls.length(), 1)
  assert_true(result is [Ok({ confirmed: true, .. })])
}

///|
test "foreground compare and file pages overlap and independent validation waits for both" {
  let (client, n) = snapshot_harness()
  client.load_snapshot(snapshot_args(), 1, _ => ())
  n.reply_metadata(snapshot_pull(count=112))
  assert_eq(n.calls.length(), 3)
  n.reply_files(Array::makei(100, snapshot_file))
  n.reply_files(Array::makei(12, i => snapshot_file(i + 100)))
  assert_eq(n.calls.length(), 4)
  assert_true(n.pending_stage("metadata") is None)
  n.reply_compare()
  assert_eq(n.calls.length(), 5)
  assert_true(n.last().request() is PullGet(_))
}

///|
test "metadata-only candidates revalidate after thirty seconds in a later home visit" {
  let (client, n) = snapshot_harness()
  let candidates = [{ pull: snapshot_args(), updated_at: "v1", }]
  client.prefetch_home(candidates, 0)
  n.tick()
  n.reply_metadata(snapshot_pull(count=301))
  assert_eq(n.calls.length(), 1)
  client.stop_prefetch()
  client.workspace.cache = client.workspace.cache.map(entry => {
    ..entry,
    created: 0,
  })
  client.prefetch_home(candidates, 0)
  n.tick()
  assert_eq(n.calls.length(), 2)
  assert_true(n.last().request() is PullGet(_))
}

///|
test "clicking during a background comparison starts the missing file chain immediately" {
  let (client, n) = snapshot_harness()
  client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
  n.tick()
  n.reply_metadata(snapshot_pull(count=1))
  assert_true(n.last().request() is CompareGet(_))
  let results = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  assert_true(n.last().request() is PullFiles(_))
  n.reply_files([snapshot_file(0)])
  assert_true(n.pending_stage("metadata") is None)
  n.reply_compare()
  n.reply_metadata(snapshot_pull(count=1))
  assert_true(results is [Ok({ confirmed: true, .. })])
  assert_eq(n.calls.length(), 4)
}
