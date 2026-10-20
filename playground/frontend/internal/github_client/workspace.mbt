///|
pub type PullSnapshot = @protocol.ApiPullSnapshot

///|
pub(all) struct SnapshotResult {
  snapshot : PullSnapshot
  confirmed : Bool
} derive(Eq)

///|
pub(all) struct PrefetchCandidate {
  pull : @protocol.PullGet
  updated_at : String
} derive(Eq)

///|
priv enum Payload {
  Snapshot(PullSnapshot)
  Source(@protocol.ApiSource)
  Metadata(@protocol.ApiPull)
}

///|
priv struct CacheEntry {
  key : String
  payload : Payload
  bytes : Int32
  created : Double
  hint : String
}

///|
priv struct ReadWaiter {
  owner : Int32
  done : (Result[@protocol.RpcValue, Error]) -> Unit
}

///|
priv struct SharedRead {
  wire_owner : Int32
  mut active : Bool
  mut waiters : Array[ReadWaiter]
}

///|
priv struct SnapshotWaiter {
  generation : Int32
  done : (Result[SnapshotResult, Error]) -> Unit
}

///|
priv struct SnapshotTask {
  id : Int32
  epoch : Int32
  args : @protocol.PullGet
  mut background : Bool
  mut active : Bool
  mut attempt : Int32
  mut waiters : Array[SnapshotWaiter]
  hint : String
  mut metadata_only : Bool
  mut comparison : @protocol.ApiCompare?
  mut files : Array[@protocol.ApiFile]?
  mut validating : Bool
  mut full_prefetch : Bool
  mut metadata : @protocol.ApiPull?
  mut files_started : Bool
}

///|
priv struct DeferredWork {
  resolve : () -> Unit
  reject : (Error) -> Unit
}

///|
priv struct Workspace {
  mut user : String?
  mut epoch : Int32
  mut checking : Bool
  mut identity_error : Error?
  mut serial : Int32
  reads : Map[String, SharedRead]
  tasks : Map[String, SnapshotTask]
  mut cache : Array[CacheEntry]
  mut bytes : Int32
  mut deferred : Array[DeferredWork]
  mut invalidated : () -> Unit
  mut home_revision : Int32
  mut home : Bool
  mut prefetch_ready : Bool
  mut candidates : Array[PrefetchCandidate]
  mut round : Int32
  mut index : Int32
  mut full_prefetches : Int32
  mut cancel_intent : () -> Unit
  mut source_queue : Array[(String, @protocol.ContentGet)]
  mut source_index : Int32
  mut background_source : @protocol.ContentGet?
  mut background_key : String?
  mut background_owner : Int32?
  mut cancel_delay : () -> Unit
  mut limited : Bool
  attempted : Map[String, String]
}

///|
fn Workspace::new() -> Workspace {
  {
    user: None,
    epoch: 0,
    checking: true,
    identity_error: None,
    serial: 0,
    reads: {},
    tasks: {},
    cache: [],
    bytes: 0,
    deferred: [],
    invalidated: () => (),
    home_revision: 0,
    home: false,
    prefetch_ready: false,
    candidates: [],
    round: 0,
    index: 0,
    full_prefetches: 0,
    cancel_intent: () => (),
    source_queue: [],
    source_index: 0,
    background_source: None,
    background_key: None,
    background_owner: None,
    cancel_delay: () => (),
    limited: false,
    attempted: {},
  }
}

///|
fn pull_key(args : @protocol.PullGet) -> String {
  "pull:\{args.owner.to_lower()}/\{args.repo.to_lower()}/\{args.number}"
}

///|
fn payload_bytes(payload : Payload) -> Int32 {
  let text = match payload {
    Snapshot(snapshot) =>
      ToJson::to_json(snapshot.metadata).stringify() +
      ToJson::to_json(snapshot.comparison).stringify() +
      ToJson::to_json(snapshot.files).stringify() +
      snapshot.signature
    Source(source) => ToJson::to_json(source).stringify()
    Metadata(metadata) => ToJson::to_json(metadata).stringify()
  }
  @utf8.encode(text).length()
}

///|
const CACHE_BUDGET : Int32 = 32 * 1048576

///|
const REVALIDATE_INTERVAL : Double = 30000

///|
fn Workspace::remove_cache(self : Workspace, key : String) -> Unit {
  self.cache = self.cache.filter(entry => {
    if entry.key == key {
      self.bytes -= entry.bytes
      false
    } else {
      true
    }
  })
}

///|
fn Workspace::store(
  self : Workspace,
  key : String,
  payload : Payload,
  now : Double,
  hint~ : String = "",
) -> Unit {
  self.remove_cache(key)
  let bytes = payload_bytes(payload)
  if bytes > CACHE_BUDGET {
    return
  }
  while self.bytes + bytes > CACHE_BUDGET {
    let old = self.cache[0]
    self.bytes -= old.bytes
    self.cache = self.cache[1:].to_owned()
    @metrics.counter("prefetch_evictions", 1)
  }
  self.cache.push({ key, payload, bytes, created: now, hint, })
  self.bytes += bytes
  @metrics.state("prefetch", "cache_bytes", self.bytes)
}

///|
fn Workspace::cached(
  self : Workspace,
  key : String,
  _now : Double,
  hint~ : String = "",
) -> Payload? {
  guard !self.checking else { return None }
  guard self.cache.search_by(entry => entry.key == key) is Some(index) else {
    return None
  }
  let entry = self.cache[index]
  // Hints describe freshness, never whether a retained version is readable.
  ignore(hint)
  self.cache = self.cache.filter(item => item.key != key)
  self.cache.push(entry)
  Some(entry.payload)
}

///|
fn Workspace::recent(
  self : Workspace,
  key : String,
  now : Double,
  hint~ : String = "",
) -> Payload? {
  guard self.cache.iter().find_first(entry => entry.key == key) is Some(entry) &&
    now - entry.created < REVALIDATE_INTERVAL &&
    (hint.is_empty() || entry.hint.is_empty() || entry.hint == hint) else {
    return None
  }
  self.cached(key, now)
}

///|
fn metadata_key(args : @protocol.PullGet) -> String {
  "metadata:" + pull_key(args)
}

///|
fn Client::clear_workspace(self : Client) -> Unit {
  let w = self.workspace
  w.epoch += 1
  w.home = false
  w.prefetch_ready = false
  w.round += 1
  (w.cancel_delay)()
  (w.cancel_intent)()
  w.cancel_delay = () => ()
  w.candidates = []
  w.source_queue = []
  w.attempted.clear()
  w.background_owner = None
  w.background_key = None
  w.background_source = None
  for _, task in w.tasks {
    task.active = false
    task.waiters.clear()
  }
  w.tasks.clear()
  let reads = w.reads.values().collect()
  w.reads.clear()
  for read in reads {
    read.active = false
    self.cancel_pending(p => p.generation == read.wire_owner)
    self.cancel_public_owner(read.wire_owner)
    for waiter in read.waiters {
      (waiter.done)(Err(Cancelled))
    }
    read.waiters.clear()
  }
  self.cancel_pending(p => p.generation > 0 && !p.auth)
  w.cache = []
  w.bytes = 0
  w.deferred = []
  @metrics.state("prefetch", "cache_bytes", 0)
}

///|
fn Client::workspace_identity(
  self : Client,
  status : @protocol.ApiAuthStatus,
) -> Unit {
  let next = if status.authenticated { status.user_id } else { None }
  if self.workspace.user is None && !self.authenticated && status.authenticated {
    // Unauthenticated reads have no private credentials or data. Let their
    // current subscribers finish when signing in for the first time.
    self.workspace.cache = []
    self.workspace.bytes = 0
    // Mutable PR reads must restart with the new credentials: an anonymous
    // permission failure may still be pending. Fixed-SHA source reads can finish.
    let tasks = self.workspace.tasks.values().collect()
    for task in tasks {
      self.cancel_snapshot(task)
    }
  } else if self.workspace.user != next ||
    self.authenticated != status.authenticated {
    self.clear_workspace()
  }
  self.workspace.user = next
}

///|
fn Client::deliver_snapshot(
  self : Client,
  task : SnapshotTask,
  result : Result[SnapshotResult, Error],
) -> Unit {
  let epoch = task.epoch
  let waiters = task.waiters.copy()
  let authenticated = self.authenticated
  let deliver = result => {
    if self.workspace.epoch == epoch {
      for waiter in waiters {
        if waiter.generation >= self.generation {
          (waiter.done)(result)
        }
      }
    }
  }
  let work : DeferredWork = {
    resolve: () => deliver(result),
    reject: error => deliver(if authenticated { Err(error) } else { result }),
  }
  if self.workspace.checking {
    self.workspace.deferred.push(work)
  } else if self.workspace.identity_error is Some(error) {
    (work.reject)(error)
  } else {
    (work.resolve)()
  }
}

///|
fn Client::cache_payload(
  self : Client,
  key : String,
  payload : Payload,
  now : Double,
  hint~ : String = "",
) -> Unit {
  if self.authenticated && self.workspace.user is None {
    return
  }
  // The legacy public immutable cache shares the same total payload budget.
  self.public_cache = []
  self.public_cache_bytes = 0
  self.workspace.store(key, payload, now, hint~)
}
