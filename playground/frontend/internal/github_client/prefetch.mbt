///|
fn Client::cancel_snapshot(self : Client, task : SnapshotTask) -> Unit {
  task.active = false
  task.waiters.clear()
  self.workspace.tasks.remove(pull_key(task.args))
  if self.workspace.background_owner == Some(-task.id) {
    self.workspace.background_owner = None
    self.workspace.background_key = None
  }
  self.cancel_reads(owner => owner == -task.id)
}

///|
fn Client::stop_prefetch(self : Client, keep~ : String = "") -> Unit {
  let w = self.workspace
  w.home = false
  w.prefetch_ready = false
  w.round += 1
  (w.cancel_delay)()
  (w.cancel_intent)()
  w.cancel_intent = () => ()
  w.cancel_delay = () => ()
  let tasks = w.tasks.values().collect()
  for task in tasks {
    if task.background && pull_key(task.args) != keep {
      self.cancel_snapshot(task)
    }
  }
  if w.background_key != Some(keep) && w.background_owner is Some(owner) {
    w.background_owner = None
    w.background_key = None
    w.background_source = None
    self.cancel_reads(id => id == owner)
  }
}

///|
fn first_source_args(
  args : @protocol.PullGet,
  snapshot : PullSnapshot,
) -> Array[@protocol.ContentGet] {
  guard snapshot.files
    .iter()
    .find_first(file => {
      @github.is_moonbit_file(file.filename) ||
      file.previous_filename.map(@github.is_moonbit_file).unwrap_or(false)
    })
    is Some(file) else {
    return []
  }
  let reference = @github.pull_reference(args.owner, args.repo, args.number)
  let (old, new) = @github.pull_revisions(
    reference,
    snapshot.metadata,
    snapshot.comparison,
  )
  let pair = @github.source_pair_for_revisions(old, new, file)
  let sources : Array[@protocol.ContentGet] = []
  for location in [pair.old_location, pair.new_location] {
    if location is Some(location) {
      sources.push({
        owner: location.repository.owner,
        repo: location.repository.repo,
        revision: location.revision,
        path: location.path,
      })
    }
  }
  sources
}

///|
fn Client::queue_first_sources(
  self : Client,
  args : @protocol.PullGet,
  snapshot : PullSnapshot,
) -> Unit {
  for source in first_source_args(args, snapshot) {
    self.workspace.source_queue.push((pull_key(args), source))
  }
}

///|
fn Client::pump_prefetch(self : Client) -> Unit {
  let w = self.workspace
  if !(self.transport.visible)() {
    self.stop_prefetch()
    return
  }
  guard w.home &&
    w.prefetch_ready &&
    !w.checking &&
    self.authenticated &&
    w.user is Some(_) &&
    !w.limited &&
    w.background_owner is None else {
    return
  }
  // Warm each first file immediately, before starting the next candidate.
  while w.source_index < w.source_queue.length() {
    let (pull, args) = w.source_queue[w.source_index]
    w.source_index += 1
    let request = @protocol.GitHubRequest::ContentGet(args)
    let key = request.encode().stringify()
    if w.cached(key, @browser.date_now()) is Some(_) {
      continue
    }
    if w.attempted.contains(key) {
      continue
    }
    w.serial += 1
    let owner = -w.serial
    let epoch = w.epoch
    w.background_owner = Some(owner)
    w.background_key = Some(pull)
    w.background_source = Some(args)
    self.read(
      request,
      owner,
      result => {
        guard w.epoch == epoch && w.background_owner == Some(owner) else {
          return
        }
        w.background_owner = None
        w.background_key = None
        w.background_source = None
        if result is Err(error) && rate_limited(error) {
          w.limited = true
        }
        if result is Err(_) {
          w.attempted[key] = ""
        }
        self.pump_prefetch()
      },
      background=true,
    )
    return
  }
  while w.index < w.candidates.length() {
    let candidate = w.candidates[w.index]
    w.index += 1
    let key = pull_key(candidate.pull)
    let now = @browser.date_now()
    if w.tasks.contains(key) ||
      w.attempted.get(key) == Some(candidate.updated_at) {
      continue
    }
    let cached = match w.cached(key, now) {
      Some(Snapshot(snapshot)) => Some(snapshot)
      _ => None
    }
    if w.recent(key, now, hint=candidate.updated_at) is Some(Snapshot(snapshot)) {
      if w.full_prefetches < 2 {
        w.full_prefetches += 1
        self.queue_first_sources(candidate.pull, snapshot)
        self.pump_prefetch()
        return
      }
      continue
    }
    let metadata = match
      w.recent(metadata_key(candidate.pull), now, hint=candidate.updated_at) {
      Some(Metadata(pull)) => Some(pull)
      _ => None
    }
    if metadata is Some(_) && w.full_prefetches >= 2 {
      continue
    }
    let task = self.new_snapshot_task(
      candidate.pull,
      true,
      candidate.updated_at,
      [],
    )
    task.metadata_only = w.full_prefetches >= 2
    w.background_owner = Some(-task.id)
    w.background_key = Some(key)
    if metadata is Some(pull) && cached is None {
      self.build_snapshot(task, pull)
    } else {
      self.snapshot_metadata(task, cached)
    }
    return
  }
}

///|
fn Client::prefetch_home(
  self : Client,
  candidates : Array[PrefetchCandidate],
  revision : Int32,
) -> Unit {
  let candidates = candidates[:Int32::min(5, candidates.length())].to_owned()
  let w = self.workspace
  guard (self.transport.visible)() && self.authenticated && w.user is Some(_) else {
    self.stop_prefetch()
    return
  }
  if w.home && w.candidates == candidates && w.home_revision == revision {
    return
  }
  let new_round = w.home_revision != revision || w.candidates != candidates
  w.home_revision = revision
  if new_round {
    w.attempted.clear()
    w.limited = false
  }
  let tasks = w.tasks.values().collect()
  for task in tasks {
    if task.background &&
      !candidates.any(candidate => {
        pull_key(candidate.pull) == pull_key(task.args) &&
        candidate.updated_at == task.hint
      }) {
      if w.background_owner == Some(-task.id) {
        w.background_owner = None
        w.background_key = None
      }
      self.cancel_snapshot(task)
    }
  }
  if w.background_source is Some(_) &&
    !candidates.any(candidate => {
      w.background_key == Some(pull_key(candidate.pull))
    }) &&
    w.background_owner is Some(owner) {
    w.background_owner = None
    w.background_key = None
    w.background_source = None
    self.cancel_reads(id => id == owner)
  }
  w.home = true
  w.prefetch_ready = false
  w.candidates = candidates.copy()
  w.index = 0
  w.full_prefetches = w.tasks
    .values()
    .filter(task => task.background && task.full_prefetch)
    .count()
  w.source_queue = []
  w.source_index = 0
  w.round += 1
  let round = w.round
  let epoch = w.epoch
  (w.cancel_delay)()
  w.cancel_delay = (self.transport.delay)(250, () => {
    if w.home && round == w.round && epoch == w.epoch {
      w.prefetch_ready = true
      self.pump_prefetch()
    }
  })
}

///|
pub fn prefetch_home(
  candidates : Array[PrefetchCandidate],
  revision : Int32,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => client.prefetch_home(candidates, revision))
}

///|
pub fn stop_prefetch() -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => client.stop_prefetch())
}

///|
fn Client::prefetch_intent(
  self : Client,
  args : @protocol.PullGet?,
  focused : Bool,
) -> Unit {
  let w = self.workspace
  (w.cancel_intent)()
  w.cancel_intent = () => ()
  guard focused && w.home && args is Some(args) else { return }
  let key = pull_key(args)
  guard w.candidates.any(candidate => pull_key(candidate.pull) == key) else {
    return
  }
  let epoch = w.epoch
  let round = w.round
  w.cancel_intent = (self.transport.delay)(100, () => {
    guard w.home &&
      w.epoch == epoch &&
      w.round == round &&
      (self.transport.visible)() else {
      return
    }
    if w.candidates.search_by(candidate => pull_key(candidate.pull) == key)
      is Some(index) &&
      index >= w.index {
      let candidate = w.candidates[index]
      let reordered = w.candidates[:w.index].to_owned()
      reordered.push(candidate)
      for i in w.index..<w.candidates.length() {
        if i != index {
          reordered.push(w.candidates[i])
        }
      }
      w.candidates = reordered
    }
    self.pump_prefetch()
  })
}

///|
pub fn prefetch_intent(
  args : @protocol.PullGet?,
  focused : Bool,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => client.prefetch_intent(args, focused))
}
