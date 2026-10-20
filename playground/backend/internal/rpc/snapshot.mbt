///|
priv struct SnapshotEntry {
  key : String
  snapshot : @protocol.ApiPullSnapshot
  bytes : Int32
}

///|
priv struct SnapshotCache {
  mut entries : Array[SnapshotEntry]
  mut bytes : Int32
}

///|
const SNAPSHOT_CACHE_BUDGET : Int32 = 64 * 1048576

///|
// One process-wide budget, with each entry isolated by session and auth epoch.
let snapshots : SnapshotCache = { entries: [], bytes: 0, }

///|
fn SnapshotCache::remove(self : SnapshotCache, key : String) -> Unit {
  self.entries = self.entries.filter(entry => {
    if entry.key == key {
      self.bytes -= entry.bytes
      false
    } else {
      true
    }
  })
}

///|
fn snapshot_bytes(snapshot : @protocol.ApiPullSnapshot) -> Int32 {
  let response : @protocol.Response[@protocol.RpcValue] = Success(
    value=PullSnapshot(Complete(snapshot)),
  )
  @utf8.encode(ToJson::to_json(response).stringify()).length()
}

///|
fn SnapshotCache::store(
  self : SnapshotCache,
  key : String,
  snapshot : @protocol.ApiPullSnapshot,
) -> Unit {
  self.remove(key)
  let bytes = snapshot_bytes(snapshot)
  if bytes > @protocol.SNAPSHOT_BYTE_LIMIT {
    return
  }
  while self.bytes + bytes > SNAPSHOT_CACHE_BUDGET {
    let entry = self.entries[0]
    self.bytes -= entry.bytes
    self.entries = self.entries[1:].to_owned()
  }
  self.entries.push({ key, snapshot, bytes, })
  self.bytes += bytes
}

///|
async fn snapshot_metadata(
  app : @storage.App,
  session : @storage.Session,
  args : @protocol.PullGet,
) -> @protocol.ApiPull {
  let request = @protocol.GitHubRequest::PullGet(args)
  @common.decode_github(
    @github.github_json(app, Some(session), request.public_path().unwrap()),
  )
}

///|
async fn snapshot_files(
  app : @storage.App,
  session : @storage.Session,
  args : @protocol.PullGet,
  metadata : @protocol.ApiPull,
) -> Array[@protocol.ApiFile]? {
  let files : Array[@protocol.ApiFile] = []
  let mut bytes = @utf8.encode(ToJson::to_json(metadata).stringify()).length()
  if bytes > @protocol.SNAPSHOT_BYTE_LIMIT {
    return None
  }
  for page in 1..<=3 {
    if files.length() >= metadata.changed_files {
      break
    }
    let request = @protocol.GitHubRequest::PullFiles({
      owner: args.owner,
      repo: args.repo,
      number: args.number,
      page,
    })
    let loaded : Array[@protocol.ApiFile] = @common.decode_github(
      @github.github_json(app, Some(session), request.public_path().unwrap()),
    )
    guard loaded.length() <= 100 else {
      raise @common.RpcError(
        502, "invalid_github_response", "GitHub returned an invalid file page.",
      )
    }
    for file in loaded {
      bytes += @utf8.encode(ToJson::to_json(file).stringify()).length() + 1
      if bytes > @protocol.SNAPSHOT_BYTE_LIMIT ||
        files.length() >= @protocol.SNAPSHOT_FILE_LIMIT {
        return None
      }
      files.push(file)
    }
    if loaded.length() < 100 {
      break
    }
  }
  Some(files)
}

///|
async fn pull_snapshot(
  app : @storage.App,
  session : @storage.Session?,
  args : @protocol.PullGet,
) -> @protocol.ApiPullSnapshotResult {
  guard session is Some(session) && !session.tokens.is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "Sign in to GitHub to continue.",
    )
  }
  let session = @github.authenticated(app, session)
  let key = "\{session.id}:\{session.epoch}:\{args.owner.to_lower()}/\{args.repo.to_lower()}/\{args.number}"
  let mut metadata = snapshot_metadata(app, session, args)
  if snapshots.entries.iter().find_first(entry => entry.key == key)
    is Some(entry) &&
    @protocol.same_pull_snapshot(entry.snapshot.metadata, metadata) {
    let snapshot = { ..entry.snapshot, metadata, }
    if snapshot_bytes(snapshot) > @protocol.SNAPSHOT_BYTE_LIMIT {
      snapshots.remove(key)
      return MetadataOnly(metadata)
    }
    snapshots.store(key, snapshot)
    return Complete(snapshot)
  }
  snapshots.remove(key)
  for attempt in 0..<=1 {
    if metadata.changed_files > @protocol.SNAPSHOT_FILE_LIMIT {
      return MetadataOnly(metadata)
    }
    let before = metadata
    // Compare and the sequential file-page chain use at most two upstream reads.
    let (comparison, files) = @async.with_task_group(group => {
      let comparison = group.spawn(() => {
        let request = @protocol.GitHubRequest::CompareGet({
          owner: args.owner,
          repo: args.repo,
          base: before.base.sha,
          head: before.head.sha,
        })
        (
          @common.decode_github(
            @github.github_json(
              app,
              Some(session),
              request.public_path().unwrap(),
            ),
          ) : @protocol.ApiCompare)
      })
      let files = snapshot_files(app, session, args, before)
      (comparison.wait(), files)
    })
    guard files is Some(files) else { return MetadataOnly(before) }
    // This is deliberately independent and starts after both chains complete.
    metadata = snapshot_metadata(app, session, args)
    if @protocol.same_pull_snapshot(before, metadata) &&
      files.length() == metadata.changed_files {
      let snapshot : @protocol.ApiPullSnapshot = {
        metadata,
        comparison,
        files,
        signature: @protocol.snapshot_signature(metadata, comparison),
      }
      if snapshot_bytes(snapshot) > @protocol.SNAPSHOT_BYTE_LIMIT {
        return MetadataOnly(metadata)
      }
      snapshots.store(key, snapshot)
      return Complete(snapshot)
    }
    if attempt == 1 {
      raise @common.RpcError(
        409, "pull_snapshot_changed", "This pull request changed while it was loading. Please try again.",
      )
    }
  }
  MetadataOnly(metadata)
}
