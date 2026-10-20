///|
test "pull snapshot is a validated read-only v2 operation" {
  let request = @protocol.GitHubRequest::PullSnapshotGet({
    owner: "alice",
    repo: "repo",
    number: "123",
  })
  assert_false(request.is_write())
  assert_true(request.public_path() is None)
  assert_true(@protocol.decode_request(request.encode()) == request)
  let invalid = @protocol.GitHubRequest::PullSnapshotGet({
    owner: "alice",
    repo: "repo",
    number: "0",
  })
  try invalid.validate() catch {
    @protocol.ProtocolError("invalid_arguments", _) => ()
    error => raise error
  } noraise {
    _ => fail("invalid pull number")
  }
}

///|
test "complete and metadata-only snapshot results roundtrip with a semantic signature" {
  let metadata : @protocol.ApiPull = {
    title: "Snapshot",
    html_url: "url",
    base: { sha: "a".repeat(40), repo: None, },
    head: { sha: "b".repeat(40), repo: Some({ full_name: "fork/repo", }), },
    additions: 0,
    deletions: 0,
    changed_files: 0,
    commits: Some(0),
  }
  let comparison : @protocol.ApiCompare = {
    merge_base_commit: { sha: "c".repeat(40), },
  }
  let signature = @protocol.snapshot_signature(metadata, comparison)
  let complete = @protocol.RpcValue::PullSnapshot(
    Complete({ metadata, comparison, files: [], signature, }),
  )
  roundtrip(complete)
  roundtrip(@protocol.RpcValue::PullSnapshot(MetadataOnly(metadata)))
  assert_true(
    @protocol.same_pull_snapshot(metadata, {
      ..metadata,
      title: "Renamed",
      additions: 100,
    }),
  )
  assert_false(
    @protocol.same_pull_snapshot(metadata, {
      ..metadata,
      head: { ..metadata.head, repo: None, },
    }),
  )
  assert_eq(
    signature,
    @protocol.snapshot_signature({ ..metadata, title: "Renamed", }, comparison),
  )
}
