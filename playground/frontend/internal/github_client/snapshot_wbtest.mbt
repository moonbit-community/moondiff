///|
fn snapshot_harness() -> (Client, Network) {
  let (client, network) = harness()
  client.adopt_status(status_fixture(phase=Completed), false)
  (client, network)
}

///|
fn snapshot_args(number~ : String = "1") -> @protocol.PullGet {
  { owner: "upstream", repo: "repo", number, }
}

///|
fn snapshot_pull(
  count~ : Int32 = 0,
  head~ : String = "b".repeat(40),
) -> @protocol.ApiPull {
  {
    title: "Snapshot fixture",
    html_url: "https://github.com/upstream/repo/pull/1",
    base: { sha: "a".repeat(40), repo: Some({ full_name: "upstream/repo", }), },
    head: { sha: head, repo: Some({ full_name: "fork/repo", }), },
    additions: count,
    deletions: 0,
    changed_files: count,
    commits: Some(0),
  }
}

///|
fn snapshot_file(index : Int32) -> @protocol.ApiFile {
  {
    filename: "src/file\{index}.mbt",
    previous_filename: None,
    status: "modified",
    additions: 1,
    deletions: 1,
    changes: 2,
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  }
}

///|
fn snapshot_comparison() -> @protocol.ApiCompare {
  { merge_base_commit: { sha: "c".repeat(40), }, }
}

///|
fn TestCall::request(self : TestCall) -> @protocol.GitHubRequest {
  @protocol.decode_request(@json.parse(self.body)) catch {
    _ => abort("request")
  }
}

///|
fn finish_fixture(
  network : Network,
  pull : @protocol.ApiPull,
  files : Array[@protocol.ApiFile],
) -> Unit {
  network.reply_metadata(pull)
  network.reply_compare()
  network.reply_files(files)
  network.reply_metadata(pull)
}

///|
test "a snapshot validates after all file pages and shares same-stage reads" {
  let (client, n) = snapshot_harness()
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  n.reply_metadata(snapshot_pull(count=101))
  n.reply_compare()
  assert_eq(n.calls.length(), 3)
  assert_true(n.last().request() is PullFiles({ page: 1, .. }))
  n.reply_files(Array::makei(100, snapshot_file))
  assert_true(n.last().request() is PullFiles({ page: 2, .. }))
  assert_true(results.is_empty())
  let duplicate : Array[Result[@protocol.RpcValue, Error]] = []
  client.read(
    PullFiles({ owner: "upstream", repo: "repo", number: "1", page: 2, }),
    1,
    result => duplicate.push(result),
  )
  assert_eq(n.calls.length(), 4)
  n.reply_files([snapshot_file(100)])
  assert_eq(duplicate.length(), 1)
  assert_true(n.last().request() is PullGet(_))
  assert_eq(n.calls.length(), 5)
  n.reply_metadata(snapshot_pull(count=101))
  assert_true(
    results is [Ok({ confirmed: true, snapshot: { files, .. }, })] &&
    files.length() == 101,
  )
}

///|
test "foreground joins and promotes an in-progress prefetch before homepage cancellation" {
  let (client, n) = snapshot_harness()
  client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
  assert_true(n.calls.is_empty())
  assert_eq(n.timers[0].ms, 250)
  n.tick()
  let initial = n.last()
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 2, result => results.push(result))
  assert_eq(n.calls.length(), 1)
  assert_false(initial.aborted)
  assert_false(client.workspace.home)
  finish_fixture(n, snapshot_pull(), [])
  assert_eq(n.calls.length(), 4)
  assert_true(results is [Ok({ confirmed: true, .. })])
  assert_true(client.workspace.tasks.is_empty())
}

///|
test "completed cache paints first but rechecks with a separate real metadata request" {
  let (client, n) = snapshot_harness()
  client.load_snapshot(snapshot_args(), 1, _ => ())
  finish_fixture(n, snapshot_pull(), [])
  client.read(PullGet(snapshot_args()), 0, _ => ())
  let older_metadata = n.last()
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 2, result => results.push(result))
  assert_true(results is [Ok({ confirmed: false, .. })])
  assert_eq(n.calls.length(), 6)
  older_metadata.reply(@protocol.RpcValue::Pull(snapshot_pull()))
  assert_eq(results.length(), 1)
  n.reply_metadata(snapshot_pull())
  assert_true(
    results is [Ok({ confirmed: false, .. }), Ok({ confirmed: true, .. })],
  )
}

///|
test "snapshot drift including fork repository changes retries at most once" {
  let (client, n) = snapshot_harness()
  let before = snapshot_pull()
  let changed = {
    ..before,
    head: { ..before.head, repo: Some({ full_name: "other/repo", }), },
  }
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  n.reply_metadata(before)
  n.reply_compare()
  n.reply_files([])
  n.reply_metadata(changed)
  assert_true(n.pending_stage("compare") is Some(_))
  n.reply_compare()
  n.reply_files([])
  n.reply_metadata(before)
  assert_eq(n.calls.length(), 7)
  assert_true(results is [Err(_)])
  assert_false(
    client.workspace.cache.any(entry => entry.payload is Snapshot(_)),
  )
}

///|
test "large metadata-only results are reused and huge PRs retain the selector" {
  let (client, n) = snapshot_harness()
  client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
  n.tick()
  n.reply_metadata(snapshot_pull(count=3001))
  assert_eq(n.calls.length(), 1)
  assert_true(client.workspace.tasks.is_empty())
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  assert_true(n.last().request() is CompareGet(_))
  n.reply_compare()
  n.reply_metadata(snapshot_pull(count=3001))
  assert_eq(n.calls.length(), 3)
  assert_true(
    results
    is [
      Ok(
        {
          snapshot: { files: [], metadata: { changed_files: 3001, .. }, .. },
          ..
        }
      ),
    ],
  )
}

///|
test "prefetch is serial and first source pairs use merge base, fork and exact renamed paths" {
  let (client, n) = snapshot_harness()
  let candidates = Array::makei(2, i => {
    pull: snapshot_args(number=(i + 1).to_string()),
    updated_at: "v1",
  })
  client.prefetch_home(candidates, 0)
  n.tick()
  let file = {
    ..snapshot_file(0),
    filename: "src/new name.mbt",
    previous_filename: Some("old/precise.mbt"),
  }
  finish_fixture(n, snapshot_pull(count=1), [file])
  assert_eq(n.calls.length(), 5)
  assert_true(
    n.last().request()
    is ContentGet({ owner: "upstream", revision, path: "old/precise.mbt", .. }) &&
    revision == "c".repeat(40),
  )
  n
  .last()
  .reply(
    @protocol.RpcValue::Content({
      size: 3,
      base64: "b2xk",
      content_type: "text/plain",
    }),
  )
  assert_true(
    n.last().request()
    is ContentGet({ owner: "fork", revision, path: "src/new name.mbt", .. }) &&
    revision == "b".repeat(40),
  )
  n
  .last()
  .reply(
    @protocol.RpcValue::Content({
      size: 3,
      base64: "bmV3",
      content_type: "text/plain",
    }),
  )
  assert_true(n.last().request() is PullGet({ number: "2", .. }))
  finish_fixture(n, snapshot_pull(count=1), [file])
  assert_eq(n.calls.length(), 10)
  assert_true(client.workspace.background_owner is None)
}

///|
test "first source prefetch prefers the first interface and preserves absent and renamed sides" {
  for
    interface in [
      { ..snapshot_file(1), filename: "pkg.generated.mbti", status: "added", },
      {
        ..snapshot_file(1),
        filename: "nested/pkg.generated.mbti",
        status: "removed",
      },
      {
        ..snapshot_file(1),
        filename: "nested/pkg.generated.mbti",
        previous_filename: Some("old.txt"),
      },
      {
        ..snapshot_file(1),
        filename: "new.txt",
        previous_filename: Some("old/pkg.generated.mbti"),
      },
    ] {
    let snapshot : PullSnapshot = {
      metadata: snapshot_pull(count=3),
      comparison: snapshot_comparison(),
      files: [
        snapshot_file(0),
        interface,
        { ..snapshot_file(2), filename: "later/pkg.generated.mbti", },
      ],
      signature: "fixture",
    }
    let sources = first_source_args(snapshot_args(), snapshot)
    assert_eq(
      sources.length(),
      if interface.status == "added" || interface.status == "removed" {
        1
      } else {
        2
      },
    )
    if interface.status != "added" {
      assert_eq(
        sources[0].path,
        interface.previous_filename.unwrap_or(interface.filename),
      )
      assert_eq(sources[0].owner, "upstream")
      assert_eq(sources[0].revision, "c".repeat(40))
    }
    if interface.status != "removed" {
      assert_eq(sources.last().unwrap().path, interface.filename)
      assert_eq(sources.last().unwrap().owner, "fork")
      assert_eq(sources.last().unwrap().revision, "b".repeat(40))
    }
  }
}

///|
test "retention, freshness hints, LRU and total payload budget are independent" {
  let w = Workspace::new()
  w.checking = false
  w.store("metadata", Metadata(snapshot_pull()), 1000, hint="v1")
  assert_true(w.cached("metadata", 30999, hint="v1") is Some(_))
  assert_true(w.cached("metadata", 31000, hint="v1") is Some(_))
  assert_true(w.recent("metadata", 31000, hint="v1") is None)
  assert_true(w.cached("metadata", 301000) is Some(_))
  w.store("metadata", Metadata(snapshot_pull()), 1000, hint="v1")
  assert_true(w.cached("metadata", 1001, hint="v2") is Some(_))
  assert_true(w.recent("metadata", 1001, hint="v2") is None)
  assert_true(w.recent("metadata", 1001) is Some(_))
  let large = Metadata({ ..snapshot_pull(), title: "x".repeat(4 * 1048576), })
  for i in 0..<7 {
    w.store(i.to_string(), large, 1000)
  }
  assert_true(w.cached("0", 1001) is Some(_))
  w.store("7", large, 1000)
  assert_true(w.cached("0", 1001) is Some(_))
  assert_true(w.cached("1", 1001) is None)
  assert_true(w.bytes <= CACHE_BUDGET)
  w.store(
    "oversized",
    Metadata({ ..snapshot_pull(), title: "x".repeat(CACHE_BUDGET + 1), }),
    1000,
  )
  assert_true(w.cached("oversized", 1001) is None)
}

///|
test "account boundary cancels tasks, rejects late results and suspends private cache adoption" {
  let (client, n) = snapshot_harness()
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  let previous = n.last()
  client.adopt_status(
    { ..status_fixture(phase=Completed), user_id: Some("other"), },
    false,
  )
  assert_true(previous.aborted)
  previous.reply(@protocol.RpcValue::Pull(snapshot_pull()))
  assert_true(results.is_empty())
  assert_true(client.workspace.tasks.is_empty())
  assert_true(client.workspace.cache.is_empty())
  client.workspace.store("private", Metadata(snapshot_pull()), 1000)
  client.workspace.checking = true
  assert_true(client.workspace.cached("private", 1001) is None)
  client.adopt_status(
    { ..status_fixture(phase=Completed), user_id: Some("other"), },
    false,
  )
  assert_true(client.workspace.cached("private", 1001) is Some(_))
}

///|
test "rate limiting stops the round without retrying and other errors remain per-task" {
  let (client, n) = snapshot_harness()
  let candidates = Array::makei(3, i => {
    pull: snapshot_args(number=(i + 1).to_string()),
    updated_at: "v1",
  })
  client.prefetch_home(candidates, 0)
  n.tick()
  (n.last().receive)(Err("fixture network failure"))
  assert_eq(n.calls.length(), 2)
  let failure : @protocol.Response[@protocol.RpcValue] = Failure(error={
    status: 429,
    code: "rate_limit",
    message: "Limited",
  })
  (n.last().receive)(Ok((429, ToJson::to_json(failure).stringify())))
  assert_eq(n.calls.length(), 2)
  assert_true(client.workspace.limited)
  assert_eq(n.timer_count(), 0)
}

///|
test "identity checks release each new write once with the same account's new CSRF" {
  let (client, n) = snapshot_harness()
  client.status(_ => ())
  let status = n.last()
  let results : Array[Result[@protocol.RpcValue, Error]] = []
  client.rpc(
    IssueCommentCreate({
      owner: "upstream",
      repo: "repo",
      number: "1",
      body: "deferred",
    }),
    1,
    value => value,
    result => results.push(result),
  )
  assert_eq(n.calls.length(), 1)
  status.reply(status_fixture(phase=Completed, csrf="rotated-csrf"))
  assert_eq(n.calls.length(), 2)
  assert_eq(n.last().csrf, "rotated-csrf")
  assert_true(
    n.last().request() is IssueCommentCreate({ body: "deferred", .. }),
  )
  n
  .last()
  .reply(
    @protocol.RpcValue::IssueComment({
      id: 1L,
      body: "deferred",
      html_url: "https://github.com/comment/1",
      created_at: "2026-09-01T00:00:00Z",
      user: None,
    }),
  )
  client.adopt_status(status_fixture(phase=Completed, csrf="next-csrf"), false)
  assert_eq(n.calls.length(), 2)
  assert_eq(results.length(), 1)
  assert_true(client.workspace.deferred.is_empty())
}

///|
test "account switches and sign-out discard deferred writes before adopting credentials" {
  for signed_out in [false, true] {
    let (client, n) = snapshot_harness()
    client.status(_ => ())
    let status = n.last()
    let results : Array[Result[@protocol.RpcValue, Error]] = []
    client.rpc(
      IssueCommentCreate({
        owner: "upstream",
        repo: "repo",
        number: "1",
        body: "old account",
      }),
      1,
      value => value,
      result => results.push(result),
    )
    let next = if signed_out {
      anonymous_status_fixture()
    } else {
      {
        ..status_fixture(phase=Completed, csrf="other-csrf"),
        user_id: Some("2"),
      }
    }
    status.reply(next)
    assert_eq(n.calls.length(), 1)
    assert_true(results.is_empty())
    assert_true(client.workspace.deferred.is_empty())
    assert_false(client.workspace.checking)
    assert_eq(client.workspace.user, next.user_id)
    assert_eq(client.authenticated, next.authenticated)
    assert_eq(client.csrf, next.csrf_token.unwrap_or(""))
    client.adopt_status(status_fixture(phase=Completed), false)
    assert_eq(n.calls.length(), 1)
  }
}

///|
test "identity confirmation resumes paused prefetch with the new CSRF" {
  let (client, n) = snapshot_harness()
  client.status(_ => ())
  let status = n.last()
  client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
  n.tick()
  assert_eq(n.calls.length(), 1)
  status.reply(status_fixture(phase=Completed, csrf="prefetch-csrf"))
  assert_eq(n.calls.length(), 2)
  assert_true(n.last().request() is PullGet(_))
  assert_eq(n.last().csrf, "prefetch-csrf")
}

///|
test "a cached visit adopts an identical source already warming for a different PR" {
  let (client, n) = snapshot_harness()
  client.prefetch_home(
    Array::makei(2, i => {
      pull: snapshot_args(number=(i + 1).to_string()),
      updated_at: "v1",
    }),
    0,
  )
  n.tick()
  finish_fixture(n, snapshot_pull(count=1), [snapshot_file(0)])
  client.workspace.store(
    pull_key(snapshot_args(number="2")),
    Snapshot({
      metadata: snapshot_pull(count=1),
      comparison: snapshot_comparison(),
      files: [snapshot_file(0)],
      signature: "fixture",
    }),
    @browser.date_now(),
  )
  let source = n.last()
  guard source.request() is ContentGet(args) else { fail("source") }
  client.load_snapshot(snapshot_args(number="2"), 1, _ => ())
  assert_false(source.aborted)
  let count = n.calls.length()
  let results : Array[Result[@protocol.RpcValue, Error]] = []
  client.read(ContentGet(args), 1, result => results.push(result))
  assert_eq(n.calls.length(), count)
  source.reply(
    @protocol.RpcValue::Content({
      size: 3,
      base64: "b2xk",
      content_type: "text/plain",
    }),
  )
  assert_eq(results.length(), 1)
}

///|
test "hiding cancels each background snapshot stage and rejects late cache writes" {
  for stage in 0..<5 {
    for event_received in [false, true] {
      let (client, n) = snapshot_harness()
      client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
      n.tick()
      let pull = snapshot_pull(count=1)
      if stage > 0 {
        n.reply_metadata(pull)
      }
      if stage > 1 {
        n.reply_compare()
      }
      if stage > 2 {
        n.reply_files([snapshot_file(0)])
      }
      if stage > 3 {
        n.reply_metadata(pull)
      }
      let pending = n.last()
      let count = n.calls.length()
      let bytes = client.workspace.bytes
      n.visible = false
      if event_received {
        client.stop_prefetch()
        assert_true(pending.aborted)
        assert_true(client.workspace.reads.is_empty())
      }
      let value : @protocol.RpcValue = match stage {
        0 | 3 => Pull(pull)
        1 => Compare(snapshot_comparison())
        2 => Files([snapshot_file(0)])
        _ => Content({ size: 3, base64: "b2xk", content_type: "text/plain", })
      }
      pending.reply(value)
      assert_eq(n.calls.length(), count)
      assert_eq(client.workspace.bytes, bytes)
      assert_true(client.workspace.tasks.is_empty())
      assert_true(client.workspace.reads.is_empty())
      assert_true(client.workspace.background_owner is None)
      assert_eq(n.timer_count(), 0)
    }
  }
}

///|
test "hiding cancels a paginated background file read before its next stage" {
  let (client, n) = snapshot_harness()
  let task = client.new_snapshot_task(snapshot_args(), true, "v1", [])
  client.snapshot_files(task, snapshot_pull(count=201), 2, [])
  let pending = n.last()
  n.visible = false
  pending.reply(@protocol.RpcValue::Files(Array::makei(100, snapshot_file)))
  assert_eq(n.calls.length(), 1)
  assert_true(client.workspace.tasks.is_empty())
  assert_true(client.workspace.cache.is_empty())
}

///|
test "hidden prefetch entry and delayed callbacks never start work and resumption waits 250ms" {
  let (client, n) = snapshot_harness()
  let candidates = [{ pull: snapshot_args(), updated_at: "v1", }]
  n.visible = false
  client.prefetch_home(candidates, 0)
  assert_eq(n.timer_count(), 0)
  assert_true(n.calls.is_empty())
  n.visible = true
  client.prefetch_home(candidates, 0)
  let stale = n.timers[0]
  n.visible = false
  n.tick()
  assert_true(n.calls.is_empty())
  n.visible = true
  client.prefetch_home(candidates, 0)
  assert_eq(n.timer_count(), 1)
  assert_eq(n.timers[1].ms, 250)
  (stale.run)()
  assert_true(n.calls.is_empty())
  n.tick()
  assert_eq(n.calls.length(), 1)
}

///|
test "identity callbacks cannot bypass the prefetch delay after visibility resumes" {
  let (client, n) = snapshot_harness()
  let candidates = [{ pull: snapshot_args(), updated_at: "v1", }]
  client.prefetch_home(candidates, 0)
  client.status(_ => ())
  n.last().reply(status_fixture(phase=Completed))
  assert_eq(n.calls.length(), 1)
  assert_eq(n.timer_count(), 1)
  n.tick()
  assert_eq(n.calls.length(), 2)
  client.stop_prefetch()
  client.prefetch_home(candidates, 0)
  client.adopt_status(status_fixture(phase=Completed), false)
  assert_eq(n.calls.length(), 2)
  n.tick()
  assert_eq(n.calls.length(), 3)
}

///|
test "hiding releases background subscriptions but shared foreground reads and promoted tasks finish" {
  for source in [false, true] {
    let (client, n) = snapshot_harness()
    client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
    n.tick()
    if source {
      finish_fixture(n, snapshot_pull(count=1), [snapshot_file(0)])
    }
    let pending = n.last()
    let results : Array[Result[@protocol.RpcValue, Error]] = []
    client.read(pending.request(), 1, result => results.push(result))
    let count = n.calls.length()
    n.visible = false
    client.stop_prefetch()
    assert_false(pending.aborted)
    let value : @protocol.RpcValue = if source {
      Content({ size: 3, base64: "b2xk", content_type: "text/plain", })
    } else {
      Pull(snapshot_pull())
    }
    pending.reply(value)
    assert_true(results is [Ok(_)])
    assert_eq(n.calls.length(), count)
    assert_true(client.workspace.tasks.is_empty())
  }
  let (client, n) = snapshot_harness()
  client.prefetch_home([{ pull: snapshot_args(), updated_at: "v1", }], 0)
  n.tick()
  let results : Array[Result[SnapshotResult, Error]] = []
  client.load_snapshot(snapshot_args(), 1, result => results.push(result))
  n.visible = false
  client.stop_prefetch()
  assert_false(n.last().aborted)
  finish_fixture(n, snapshot_pull(), [])
  assert_true(results is [Ok({ confirmed: true, .. })])
}

///|
test "visibility resumption retains failures and limits until candidates or list revision change" {
  for limited in [false, true] {
    let (client, n) = snapshot_harness()
    let candidates = [{ pull: snapshot_args(), updated_at: "v1", }]
    client.prefetch_home(candidates, 0)
    n.tick()
    let response : @protocol.Response[@protocol.RpcValue] = Failure(error={
      status: if limited {
        429
      } else {
        503
      },
      code: if limited {
        "rate_limit"
      } else {
        "unavailable"
      },
      message: "fixture failure",
    })
    (n.last().receive)(Ok((503, ToJson::to_json(response).stringify())))
    client.stop_prefetch()
    client.prefetch_home(candidates, 0)
    n.tick()
    assert_eq(n.calls.length(), 1)
    assert_eq(client.workspace.limited, limited)
    assert_eq(client.workspace.attempted.length(), 1)
    client.prefetch_home(candidates, 1)
    n.tick()
    assert_eq(n.calls.length(), 2)
    assert_false(client.workspace.limited)
  }
}

///|
test "forced revalidation bypasses cached paint and existing metadata subscriptions even after TTL" {
  for expired in [false, true] {
    let (client, n) = snapshot_harness()
    client.load_snapshot(snapshot_args(), 1, _ => ())
    finish_fixture(n, snapshot_pull(), [])
    if expired {
      let entries = client.workspace.cache.copy()
      client.workspace.cache = entries.map(entry => { ..entry, created: 0, })
    }
    client.read(PullGet(snapshot_args()), 1, _ => ())
    let older = n.last()
    let results : Array[Result[SnapshotResult, Error]] = []
    client.load_snapshot(
      snapshot_args(),
      1,
      result => results.push(result),
      revalidate=true,
    )
    assert_eq(n.calls.length(), 6)
    assert_true(results.is_empty())
    older.reply(@protocol.RpcValue::Pull(snapshot_pull()))
    assert_true(results.is_empty())
    n.reply_metadata(snapshot_pull())
    assert_true(results is [Ok({ confirmed: true, .. })])
  }
}

///|
fn Network::pending_stage(self : Network, stage : String) -> TestCall? {
  self.calls
  .iter()
  .find_first(call => {
    if call.path != "/api/rpc" || call.aborted || call.answered {
      return false
    }
    match (stage, call.request()) {
      ("metadata", PullGet(_) | PullSnapshotGet(_)) => true
      ("compare", CompareGet(_)) => true
      ("files", PullFiles(_)) => true
      _ => false
    }
  })
}

///|
fn Network::reply_metadata(self : Network, pull : @protocol.ApiPull) -> Unit {
  let call = self.pending_stage("metadata").unwrap()
  call.reply(
    if call.request() is PullSnapshotGet(_) {
      @protocol.RpcValue::PullSnapshot(MetadataOnly(pull))
    } else {
      @protocol.RpcValue::Pull(pull)
    },
  )
}

///|
fn Network::reply_compare(self : Network) -> Unit {
  self
  .pending_stage("compare")
  .unwrap()
  .reply(@protocol.RpcValue::Compare(snapshot_comparison()))
}

///|
fn Network::reply_files(
  self : Network,
  files : Array[@protocol.ApiFile],
) -> Unit {
  self.pending_stage("files").unwrap().reply(@protocol.RpcValue::Files(files))
}
