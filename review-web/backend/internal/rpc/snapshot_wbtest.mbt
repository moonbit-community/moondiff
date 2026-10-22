///|
test "the process snapshot LRU accounts encoded bytes, refreshes recency and refuses oversized entries" {
  let cache : SnapshotCache = { entries: [], bytes: 0, }
  let metadata : @protocol.ApiPull = {
    title: "x".repeat(6 * 1048576),
    html_url: "url",
    base: { sha: "a".repeat(40), repo: None, },
    head: { sha: "b".repeat(40), repo: None, },
    additions: 0,
    deletions: 0,
    changed_files: 0,
    commits: None,
  }
  let snapshot : @protocol.ApiPullSnapshot = {
    metadata,
    comparison: { merge_base_commit: { sha: "c".repeat(40), }, },
    files: [],
    signature: "version",
  }
  for i in 0..<10 {
    cache.store(i.to_string(), snapshot)
  }
  cache.store("0", snapshot)
  cache.store("10", snapshot)
  assert_true(cache.entries.any(entry => entry.key == "0"))
  assert_false(cache.entries.any(entry => entry.key == "1"))
  assert_true(cache.bytes <= SNAPSHOT_CACHE_BUDGET)
  cache.store("oversized", {
    ..snapshot,
    metadata: { ..metadata, title: "x".repeat(@protocol.SNAPSHOT_BYTE_LIMIT), },
  })
  assert_false(cache.entries.any(entry => entry.key == "oversized"))
}
