///|
priv suberror Cancelled

///|
priv struct Transport {
  send : (
    String,
    String,
    String,
    String,
    (Result[(Int, String), String]) -> Unit,
  ) -> () -> Unit
  delay : (Int, () -> Unit) -> () -> Unit
}

///|
priv struct Pending {
  generation : Int
  auth : Bool
  poll : Bool
  mut active : Bool
  mut abort : () -> Unit
  cancelled : () -> Unit
}

///|
priv struct PollTask {
  token : Int
  waiters : Array[(Result[@protocol.DeviceResponse, Error]) -> Unit]
  mut cancel_timer : () -> Unit
}

///|
priv struct Client {
  transport : Transport
  mut csrf : String
  mut auth_revision : Int
  mut status_sequence : Int
  mut generation : Int
  mut device_id : String?
  mut pending_start_id : String?
  mut poll_task : PollTask?
  mut sequence : Int
  pending : Map[Int, Pending]
}

///|
fn Client::new(transport : Transport) -> Client {
  {
    transport,
    csrf: "",
    auth_revision: 0,
    status_sequence: 0,
    generation: 0,
    device_id: None,
    pending_start_id: None,
    poll_task: None,
    sequence: 0,
    pending: {},
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
fn Client::cancel_before(self : Client, generation : Int) -> Unit {
  self.generation = Int::max(self.generation, generation)
  self.cancel_pending(p => p.generation > 0 && p.generation < self.generation)
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
  self.pending_start_id = None
  self.stop_poll()
  self.cancel_pending(p => all || p.auth)
}

///|
fn Client::dispose(self : Client) -> Unit {
  self.invalidate_auth(true)
  self.device_id = None
}

///|
fn Client::adopt_status(
  self : Client,
  status : @protocol.ApiAuthStatus,
  from_poll : Bool,
) -> Unit {
  self.csrf = status.csrf_token
  let next = match status.device_flow {
    Some(flow) if flow.phase.active() => Some(flow.id)
    _ => None
  }
  if next != self.device_id && !from_poll {
    self.stop_poll()
  }
  self.device_id = next
}

///|
fn invalid_response(detail : String, status? : Int = 200) -> Error {
  HttpRequestError(status~, code="invalid_server_response", detail~)
}

///|
fn[T : FromJson + ToJson] Client::send(
  self : Client,
  path : String,
  body : String,
  completed : (Result[T, Error]) -> Unit,
  generation? : Int = 0,
  auth? : Bool = false,
  status? : Bool = false,
  poll? : Bool = false,
) -> Unit {
  self.cancel_before(generation)
  if generation > 0 && generation < self.generation {
    completed(Err(Cancelled))
    return
  }
  let revision = self.auth_revision
  if status {
    self.status_sequence += 1
  }
  let status_sequence = self.status_sequence
  self.sequence += 1
  let id = self.sequence
  let request : Pending = {
    generation,
    auth,
    poll,
    active: true,
    abort: () => (),
    cancelled: () => completed(Err(Cancelled)),
  }
  self.pending[id] = request
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
      completed(result)
    },
  )
  request.abort = cancel
}

///|
fn Client::status(
  self : Client,
  completed : (Result[@protocol.ApiAuthStatus, Error]) -> Unit,
  poll? : Bool = false,
) -> Unit {
  self.send(
    "/api/auth/status",
    "",
    result => {
      if result is Ok(status) {
        self.adopt_status(status, poll)
      }
      completed(result)
    },
    auth=true,
    status=true,
    poll~,
  )
}
