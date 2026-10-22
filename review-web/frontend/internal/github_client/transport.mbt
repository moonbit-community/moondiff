///|
priv suberror Cancelled

///|
priv struct Transport {
  visible : () -> Bool
  send : (
    String,
    String,
    String,
    String,
    (Result[(Int32, String), String]) -> Unit,
  ) -> () -> Unit
  delay : (Int32, () -> Unit) -> () -> Unit
}

///|
priv struct Pending {
  generation : Int32
  auth : Bool
  status : Bool
  poll : Bool
  mut active : Bool
  mut abort : () -> Unit
  cancelled : () -> Unit
}

///|
priv struct PollTask {
  token : Int32
  waiters : Array[(Result[@protocol.DeviceResponse, Error]) -> Unit]
  mut cancel_timer : () -> Unit
}

///|
priv struct PublicWaiter {
  generation : Int32
  done : (Result[@protocol.RpcValue, Error]) -> Unit
}

///|
priv struct PublicPending {
  mut waiters : Array[PublicWaiter]
  mut abort : () -> Unit
  mut active : Bool
}

///|
priv struct PublicCacheEntry {
  key : String
  value : @protocol.RpcValue
  bytes : Int32
}

///|
priv struct Client {
  workspace : Workspace
  transport : Transport
  mut csrf : String
  mut authenticated : Bool
  mut auth_revision : Int32
  mut status_sequence : Int32
  mut generation : Int32
  mut device_id : String?
  mut pending_start_id : String?
  mut poll_task : PollTask?
  mut sequence : Int32
  pending : Map[Int32, Pending]
  public_pending : Map[String, PublicPending]
  mut public_cache : Array[PublicCacheEntry]
  mut public_cache_bytes : Int32
}

///|
fn Client::new(transport : Transport) -> Client {
  {
    transport,
    workspace: Workspace::new(),
    csrf: "",
    authenticated: false,
    auth_revision: 0,
    status_sequence: 0,
    generation: 0,
    device_id: None,
    pending_start_id: None,
    poll_task: None,
    sequence: 0,
    pending: {},
    public_pending: {},
    public_cache: [],
    public_cache_bytes: 0,
  }
}

///|
fn Client::cancel_pending(self : Client, predicate : (Pending) -> Bool) -> Unit {
  let entries = self.pending.iter().collect()
  for (id, request) in entries {
    if request.active && predicate(request) {
      request.active = false
      self.pending.remove(id)
      (request.abort)()
      (request.cancelled)()
    }
  }
}

///|
fn Client::cancel_before(self : Client, generation : Int32) -> Unit {
  self.generation = Int32::max(self.generation, generation)
  self.cancel_pending(p => p.generation > 0 && p.generation < self.generation)
  self.cancel_public(false)
  self.cancel_reads(owner => owner > 0 && owner < self.generation)
  let tasks = self.workspace.tasks.values().collect()
  for task in tasks {
    task.waiters = task.waiters.filter(waiter => {
      waiter.generation >= self.generation
    })
    if !task.background && task.waiters.is_empty() {
      self.cancel_snapshot(task)
    }
  }
}

///|
fn Client::supersede_status(self : Client) -> Unit {
  self.status_sequence += 1
  self.cancel_pending(p => p.status)
}

///|
fn Client::stop_poll(self : Client) -> Unit {
  if self.poll_task is Some(task) {
    self.poll_task = None
    (task.cancel_timer)()
    self.cancel_pending(p => p.poll)
    for waiter in task.waiters {
      waiter(Err(Cancelled))
    }
  }
}

///|
fn Client::invalidate_auth(self : Client, all : Bool) -> Unit {
  self.auth_revision += 1
  if all {
    self.cancel_public(true)
  }
  self.pending_start_id = None
  self.stop_poll()
  self.cancel_pending(p => all || p.auth)
}

///|
fn Client::dispose(self : Client) -> Unit {
  self.stop_prefetch()
  self.invalidate_auth(true)
  self.device_id = None
}

///|
fn Client::adopt_status(
  self : Client,
  status : @protocol.ApiAuthStatus,
  from_poll : Bool,
) -> Unit {
  self.workspace_identity(status)
  self.csrf = status.csrf_token.unwrap_or("")
  self.authenticated = status.authenticated
  let next = match status.device_flow {
    Some(flow) if flow.phase.active() => Some(flow.id)
    _ => None
  }
  if next != self.device_id && !from_poll {
    self.stop_poll()
  }
  self.device_id = next
  // Release work only after every credential and device field is current.
  self.workspace.checking = false
  self.workspace.identity_error = None
  let deferred = self.workspace.deferred
  self.workspace.deferred = []
  for work in deferred {
    (work.resolve)()
  }
  self.pump_prefetch()
}

///|
fn invalid_response(detail : String, status~ : Int32 = 200) -> Error {
  HttpRequestError(status~, code="invalid_server_response", detail~)
}

///|
fn[T : FromJson + ToJson] Client::send(
  self : Client,
  path : String,
  body : String,
  completed : (Result[T, Error]) -> Unit,
  generation~ : Int32 = 0,
  auth~ : Bool = false,
  status~ : Bool = false,
  poll~ : Bool = false,
  background~ : Bool = false,
) -> Unit {
  self.cancel_before(generation)
  if generation > 0 && generation < self.generation {
    completed(Err(Cancelled))
    return
  }
  let revision = self.auth_revision
  if status {
    self.supersede_status()
  }
  let status_sequence = self.status_sequence
  self.sequence += 1
  let id = self.sequence
  let request : Pending = {
    generation,
    auth,
    status,
    poll,
    active: true,
    abort: () => (),
    cancelled: () => completed(Err(Cancelled)),
  }
  self.pending[id] = request
  @metrics.counter(
    if background {
      "prefetch_requests"
    } else {
      "foreground_requests"
    },
    1,
  )
  let cancel = (self.transport.send)(
    path,
    if status {
      "GET"
    } else {
      "POST"
    },
    self.csrf,
    body,
    result => {
      if !request.active {
        return
      }
      request.active = false
      self.pending.remove(id)
      if (auth && revision != self.auth_revision) ||
        (status && status_sequence != self.status_sequence) {
        completed(Err(Cancelled))
        return
      }
      let result : Result[T, Error] = match result {
        Err(detail) =>
          Err(HttpRequestError(status=0, code="network_error", detail~))
        Ok((http_status, text)) =>
          try {
            @metrics.counter(
              if background {
                "prefetch_bytes"
              } else {
                "foreground_bytes"
              },
              @utf8.encode(text).length(),
            )
            let response : @protocol.Response[T] = @protocol.decode(
              @json.parse(text),
            )
            match response {
              Success(value~) =>
                if http_status >= 200 && http_status < 300 {
                  Ok(value)
                } else {
                  Err(
                    invalid_response("Invalid HTTP status.", status=http_status),
                  )
                }
              Failure(error~) =>
                Err(
                  HttpRequestError(
                    status=error.status,
                    code=error.code,
                    detail=error.message,
                  ),
                )
            }
          } catch {
            _ =>
              Err(
                invalid_response(
                  "The server returned an invalid response.",
                  status=http_status,
                ),
              )
          }
      }
      if result is Err(HttpRequestError(status=401, ..)) && self.authenticated {
        self.authenticated = false
        self.clear_workspace()
        self.workspace.user = None
        (self.workspace.invalidated)()
      }
      completed(result)
    },
  )
  request.abort = cancel
}

///|
fn Client::status(
  self : Client,
  completed : (Result[@protocol.ApiAuthStatus, Error]) -> Unit,
  poll~ : Bool = false,
) -> Unit {
  self.workspace.checking = true
  self.send(
    "/api/auth/status",
    "",
    result => {
      match result {
        Ok(status) => self.adopt_status(status, poll)
        Err(Cancelled) => ()
        Err(error) => {
          self.workspace.checking = false
          // Keep the failure for private snapshots that are still loading.
          self.workspace.identity_error = Some(error)
          self.stop_prefetch()
          let deferred = self.workspace.deferred
          self.workspace.deferred = []
          for work in deferred {
            (work.reject)(error)
          }
        }
      }
      completed(result)
    },
    auth=true,
    status=true,
    poll~,
  )
}
