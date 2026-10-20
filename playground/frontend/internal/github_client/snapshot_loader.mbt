///|
fn snapshot_signature(
  pull : @protocol.ApiPull,
  comparison : @protocol.ApiCompare,
) -> String {
  @protocol.snapshot_signature(pull, comparison)
}

///|
fn Client::owns_task(self : Client, task : SnapshotTask) -> Bool {
  if task.active && task.background && !(self.transport.visible)() {
    self.stop_prefetch()
  }
  task.active &&
  task.epoch == self.workspace.epoch &&
  self.workspace.tasks
  .get(pull_key(task.args))
  .map(current => current.id == task.id)
  .unwrap_or(false)
}

///|
fn Client::new_snapshot_task(
  self : Client,
  args : @protocol.PullGet,
  background : Bool,
  hint : String,
  waiters : Array[SnapshotWaiter],
) -> SnapshotTask {
  self.workspace.serial += 1
  let task : SnapshotTask = {
    id: self.workspace.serial,
    epoch: self.workspace.epoch,
    args,
    background,
    active: true,
    attempt: 0,
    hint,
    waiters,
    metadata_only: false,
    comparison: None,
    files: None,
    validating: false,
    full_prefetch: false,
    metadata: None,
    files_started: false,
  }
  self.workspace.tasks[pull_key(args)] = task
  task
}

///|
fn Client::finish_snapshot(
  self : Client,
  task : SnapshotTask,
  result : Result[PullSnapshot, Error],
) -> Unit {
  guard self.owns_task(task) else { return }
  task.active = false
  self.workspace.tasks.remove(pull_key(task.args))
  self.cancel_reads(owner => owner == -task.id)
  match result {
    Ok(snapshot) => {
      self.cache_payload(
        pull_key(task.args),
        Snapshot(snapshot),
        @browser.date_now(),
        hint=task.hint,
      )
      self.cache_payload(
        metadata_key(task.args),
        Metadata(snapshot.metadata),
        @browser.date_now(),
        hint=task.hint,
      )
      if task.background {
        self.queue_first_sources(task.args, snapshot)
      }
      self.deliver_snapshot(task, Ok({ snapshot, confirmed: true, }))
    }
    Err(error) => {
      self.workspace.attempted[pull_key(task.args)] = task.hint
      if rate_limited(error) {
        self.workspace.limited = true
      }
      self.deliver_snapshot(task, Err(error))
    }
  }
  task.waiters.clear()
  if self.workspace.background_owner == Some(-task.id) {
    self.workspace.background_owner = None
  }
  self.pump_prefetch()
}

///|
fn snapshot_error(message : String) -> Error {
  HttpRequestError(status=409, code="pull_snapshot_changed", detail=message)
}

///|
fn Client::snapshot_read(
  self : Client,
  task : SnapshotTask,
  request : @protocol.GitHubRequest,
  done : (Result[@protocol.RpcValue, Error]) -> Unit,
  fresh~ : Bool = false,
) -> Unit {
  guard self.owns_task(task) else { return }
  self.read(
    request,
    -task.id,
    result => if self.owns_task(task) { done(result) },
    fresh~,
    background=task.background,
  )
}

///|
fn Client::validate_snapshot(
  self : Client,
  task : SnapshotTask,
  before : @protocol.ApiPull,
  comparison : @protocol.ApiCompare,
  files : Array[@protocol.ApiFile],
) -> Unit {
  // This call is made only after compare AND every file page have completed.
  // A separate fresh key cannot join an older metadata read or cache entry.
  self.snapshot_read(
    task,
    PullGet(task.args),
    result => {
      match result {
        Ok(Pull(after)) => {
          let valid = @github.same_pull_snapshot(before, after) &&
            (
              after.changed_files > @github.MAX_PULL_FILES ||
              @github.validate_pull_files(after, files) is Ok(_)
            )
          if !valid {
            if task.attempt < 1 {
              task.attempt += 1
              self.build_snapshot(task, after)
            } else {
              self.finish_snapshot(
                task,
                Err(
                  snapshot_error(
                    "This pull request changed while it was loading. Please try again.",
                  ),
                ),
              )
            }
          } else {
            self.finish_snapshot(
              task,
              Ok({
                metadata: after,
                comparison,
                files,
                signature: snapshot_signature(after, comparison),
              }),
            )
          }
        }
        Err(error) => self.finish_snapshot(task, Err(error))
        _ =>
          self.finish_snapshot(
            task,
            Err(invalid_response("Unexpected pull validation result.")),
          )
      }
    },
    fresh=true,
  )
}

///|
fn Client::snapshot_files(
  self : Client,
  task : SnapshotTask,
  metadata : @protocol.ApiPull,
  page : Int32,
  files : Array[@protocol.ApiFile],
) -> Unit {
  task.files_started = true
  self.snapshot_read(
    task,
    PullFiles({
      owner: task.args.owner,
      repo: task.args.repo,
      number: task.args.number,
      page,
    }),
    result => {
      match result {
        Ok(Files(loaded)) => {
          let accumulated = @github.merge_file_pages(files, loaded)
          if @github.should_fetch_next_pull_page(
              page,
              loaded.length(),
              accumulated.length(),
              Some(metadata.changed_files),
            ) {
            self.snapshot_files(task, metadata, page + 1, accumulated)
          } else {
            task.files = Some(accumulated)
            self.snapshot_ready(task, metadata)
          }
        }
        Err(error) => self.finish_snapshot(task, Err(error))
        _ =>
          self.finish_snapshot(
            task,
            Err(invalid_response("Unexpected pull files result.")),
          )
      }
    },
  )
}

///|
fn Client::snapshot_ready(
  self : Client,
  task : SnapshotTask,
  metadata : @protocol.ApiPull,
) -> Unit {
  if !task.validating &&
    task.comparison is Some(comparison) &&
    task.files is Some(files) {
    task.validating = true
    self.validate_snapshot(task, metadata, comparison, files)
  }
}

///|
fn Client::finish_metadata(
  self : Client,
  task : SnapshotTask,
  metadata : @protocol.ApiPull,
) -> Unit {
  self.cache_payload(
    metadata_key(task.args),
    Metadata(metadata),
    @browser.date_now(),
    hint=task.hint,
  )
  task.active = false
  self.workspace.tasks.remove(pull_key(task.args))
  if self.workspace.background_owner == Some(-task.id) {
    self.workspace.background_owner = None
    self.workspace.background_key = None
  }
  self.pump_prefetch()
}

///|
fn Client::build_snapshot(
  self : Client,
  task : SnapshotTask,
  metadata : @protocol.ApiPull,
) -> Unit {
  guard self.owns_task(task) else { return }
  self.cache_payload(
    metadata_key(task.args),
    Metadata(metadata),
    @browser.date_now(),
    hint=task.hint,
  )
  if task.background &&
    (
      task.metadata_only ||
      metadata.changed_files > @protocol.SNAPSHOT_FILE_LIMIT
    ) {
    self.finish_metadata(task, metadata)
    return
  }
  if task.background && !task.full_prefetch {
    self.workspace.full_prefetches += 1
    task.full_prefetch = true
  }
  task.metadata = Some(metadata)
  task.files_started = false
  task.comparison = None
  task.files = if metadata.changed_files > @github.MAX_PULL_FILES {
    Some([])
  } else {
    None
  }
  task.validating = false
  let parallel = !task.background
  self.snapshot_read(
    task,
    CompareGet({
      owner: task.args.owner,
      repo: task.args.repo,
      base: metadata.base.sha,
      head: metadata.head.sha,
    }),
    result => {
      match result {
        Ok(Compare(comparison)) => {
          task.comparison = Some(comparison)
          if !parallel && task.files is None && !task.files_started {
            self.snapshot_files(task, metadata, 1, [])
          } else {
            self.snapshot_ready(task, metadata)
          }
        }
        Err(error) => self.finish_snapshot(task, Err(error))
        _ =>
          self.finish_snapshot(
            task,
            Err(invalid_response("Unexpected pull compare result.")),
          )
      }
    },
  )
  if parallel && task.files is None {
    self.snapshot_files(task, metadata, 1, [])
  }
}

///|
fn Client::snapshot_metadata(
  self : Client,
  task : SnapshotTask,
  cached : PullSnapshot?,
  revalidate~ : Bool = false,
) -> Unit {
  self.snapshot_read(
    task,
    PullGet(task.args),
    result => {
      match result {
        Ok(Pull(metadata)) =>
          match cached {
            Some(snapshot) if @github.same_pull_snapshot(
                snapshot.metadata,
                metadata,
              ) =>
              if task.background && task.metadata_only {
                self.finish_metadata(task, metadata)
              } else {
                if task.background && !task.full_prefetch {
                  self.workspace.full_prefetches += 1
                  task.full_prefetch = true
                }
                self.finish_snapshot(task, Ok({ ..snapshot, metadata, }))
              }
            _ => self.build_snapshot(task, metadata)
          }
        Err(error) => self.finish_snapshot(task, Err(error))
        _ =>
          self.finish_snapshot(
            task,
            Err(invalid_response("Unexpected pull metadata result.")),
          )
      }
    },
    fresh=revalidate || cached is Some(_),
  )
}

///|
fn Client::load_snapshot(
  self : Client,
  args : @protocol.PullGet,
  generation : Int32,
  done : (Result[SnapshotResult, Error]) -> Unit,
  revalidate~ : Bool = false,
) -> Unit {
  let key = pull_key(args)
  let now = @browser.date_now()
  let cached = match self.workspace.cached(key, now) {
    Some(Snapshot(snapshot)) => Some(snapshot)
    _ => None
  }
  let waiter : SnapshotWaiter = { generation, done, }
  if self.workspace.tasks.get(key) is Some(task) && self.owns_task(task) {
    if revalidate {
      self.cancel_snapshot(task)
    } else {
      task.waiters.push(waiter)
      task.background = false
      task.metadata_only = false
      if cached is Some(snapshot) {
        self.deliver_snapshot(task, Ok({ snapshot, confirmed: false, }))
      }
      if self.workspace.background_owner == Some(-task.id) {
        self.workspace.background_owner = None
      }
      self.stop_prefetch(keep=key)
      self.cancel_before(generation)
      if task.metadata is Some(metadata) &&
        task.files is None &&
        !task.files_started {
        self.snapshot_files(task, metadata, 1, [])
      }
      @metrics.counter("prefetch_inflight_hits", 1)
      @metrics.cache_outcome(true)
      return
    }
  }
  if cached is Some(snapshot) &&
    self.workspace.background_source is Some(source) &&
    first_source_args(args, snapshot).any(needed => {
      @protocol.GitHubRequest::ContentGet(needed) == ContentGet(source)
    }) {
    self.workspace.background_key = Some(key)
  }
  let hint = self.workspace.candidates
    .iter()
    .find_first(candidate => pull_key(candidate.pull) == key)
    .map(candidate => candidate.updated_at)
    .unwrap_or("")
  let metadata = match self.workspace.recent(metadata_key(args), now, hint~) {
    Some(Metadata(pull)) => Some(pull)
    _ => None
  }
  self.stop_prefetch(keep=key)
  self.cancel_before(generation)
  let task = self.new_snapshot_task(args, false, hint, [waiter])
  if cached is Some(snapshot) {
    @metrics.counter("prefetch_cache_hits", 1)
    @metrics.cache_outcome(true)
    if !revalidate {
      self.deliver_snapshot(task, Ok({ snapshot, confirmed: false, }))
    }
    self.snapshot_metadata(task, cached, revalidate~)
  } else if !revalidate && metadata is Some(pull) {
    @metrics.counter("metadata_cache_hits", 1)
    @metrics.cache_outcome(true)
    self.build_snapshot(task, pull)
  } else {
    @metrics.counter("snapshot_misses", 1)
    @metrics.cache_outcome(false)
    if self.authenticated {
      self.snapshot_aggregate(task)
    } else {
      self.snapshot_metadata(task, None, revalidate~)
    }
  }
}

///|
fn Client::snapshot_aggregate(self : Client, task : SnapshotTask) -> Unit {
  self.snapshot_read(task, PullSnapshotGet(task.args), result => {
    match result {
      Ok(PullSnapshot(Complete(snapshot))) =>
        self.finish_snapshot(task, Ok(snapshot))
      Ok(PullSnapshot(MetadataOnly(metadata))) =>
        self.build_snapshot(task, metadata)
      Err(error) => self.finish_snapshot(task, Err(error))
      _ =>
        self.finish_snapshot(
          task,
          Err(invalid_response("Unexpected pull snapshot result.")),
        )
    }
  })
}

///|
pub fn load_pull_snapshot(
  args : @protocol.PullGet,
  generation : Int32,
  emit : @rabbita.Emit[Result[SnapshotResult, Error]],
  revalidate~ : Bool = false,
) -> @rabbita.Cmd {
  command(
    done => client.load_snapshot(args, generation, done, revalidate~),
    emit,
  )
}

///|
pub fn observe_auth_failure(callback : () -> Unit) -> Unit {
  client.workspace.invalidated = callback
}
