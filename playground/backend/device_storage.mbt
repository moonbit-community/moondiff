///|
priv struct DeviceFlow {
  session_id : String
  id : String
  target_id : String
  epoch : Int64
  phase : String
  credentials : String
  user_code : String
  verification_uri : String
  expires : Int64
  next_poll : Int64
  interval : Int64
  backoff : Int64
  token_issued : Int64
  message : String
}

///|
fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
fn DeviceFlow::active(self : DeviceFlow) -> Bool {
  ["starting", "pending", "verifying"].contains(self.phase)
}

///|
fn DeviceFlow::public_status(self : DeviceFlow) -> @protocol.ApiDeviceFlow {
  {
    id: self.id,
    phase: match self.phase {
      "starting" => Starting
      "pending" => Pending
      "verifying" => Verifying
      "completed" => Completed
      "cancelled" => Cancelled
      "expired" => Expired
      "denied" => Denied
      _ => Failed
    },
    user_code: self.user_code,
    verification_uri: self.verification_uri,
    expires_at: self.expires.to_double(),
    retry_after: if self.active() {
      Int64::max(
        0,
        Int64::min(
          self.expires - now(),
          (self.next_poll - now_ms() + 999) / 1000,
        ),
      ).to_int()
    } else {
      0
    },
    message: self.message,
  }
}

///|
fn App::device(
  self : App,
  session_id : String,
  id : String,
) -> DeviceFlow? raise {
  let stmt = self.db.prepare(
    "SELECT target_id,epoch,phase,credentials,user_code,verification_uri,expires,next_poll,interval,backoff,token_issued,message FROM authorizations WHERE session_id=? AND id=?",
  )
  defer stmt.finalize()
  stmt.bind(index=1, session_id)
  stmt.bind(index=2, id)
  guard stmt.step() else { return None }
  Some({
    session_id,
    id,
    target_id: stmt.column(index=0),
    epoch: stmt.column(index=1),
    phase: stmt.column(index=2),
    credentials: stmt.column(index=3),
    user_code: stmt.column(index=4),
    verification_uri: stmt.column(index=5),
    expires: stmt.column(index=6),
    next_poll: stmt.column(index=7),
    interval: stmt.column(index=8),
    backoff: stmt.column(index=9),
    token_issued: stmt.column(index=10),
    message: stmt.column(index=11),
  })
}

///|
fn App::end_device(
  self : App,
  flow : DeviceFlow,
  phase : String,
  message : String,
) -> Unit raise {
  execute(
    self.db,
    "UPDATE authorizations SET phase=?,credentials='',message=? WHERE session_id=? AND id=? AND phase IN ('starting','pending','verifying')",
    [Text(phase), Text(message), Text(flow.session_id), Text(flow.id)],
  )
}

///|
fn App::device_current(
  self : App,
  session_id : String,
  id : String,
) -> DeviceFlow? raise {
  guard self.device(session_id, id) is Some(flow) && flow.active() else {
    return None
  }
  if flow.expires <= now() {
    self.end_device(
      flow, "expired", "The GitHub verification code expired. Start sign-in again.",
    )
    return None
  }
  guard self.session(session_id) is Some(session) && session.epoch == flow.epoch else {
    self.end_device(flow, "cancelled", "This authorization was cancelled.")
    return None
  }
  Some(flow)
}

///|
fn App::visible_device(self : App, session : Session) -> DeviceFlow? raise {
  let id = {
    let stmt = self.db.prepare(
      "SELECT id FROM authorizations WHERE session_id=? AND phase != 'alias' ORDER BY (phase IN ('starting','pending','verifying')) DESC,epoch DESC,rowid DESC LIMIT 1",
    )
    defer stmt.finalize()
    stmt.bind(index=1, session.id)
    guard stmt.step() else { return None }
    let id : String = stmt.column(index=0)
    id
  }
  ignore(self.device_current(session.id, id))
  match self.device(session.id, id) {
    Some(flow) if flow.phase != "cancelled" && flow.phase != "completed" =>
      Some(flow)
    _ => None
  }
}

///|
// Each attempt gets a row, including attempts cancelled before start arrives.
// Aliases bind overlapping starts to the single active authorization so either
// request can cancel it even before its start response supplies the canonical ID.
fn App::begin_device(
  self : App,
  session : Session,
  attempt : String,
) -> String raise {
  guard self.session(session.id) is Some(session) else {
    raise RpcError(
      401, "authentication_required", "Session ended. Reload this page.",
    )
  }
  if self.device(session.id, attempt) is Some(previous) {
    return previous.target_id
  }
  if self.visible_device(session) is Some(flow) && flow.active() {
    execute(
      self.db,
      "INSERT INTO authorizations (session_id,id,target_id,epoch,phase,expires) VALUES (?,?,?,?,'alias',?)",
      [
        Text(session.id),
        Text(attempt),
        Text(flow.id),
        Integer(flow.epoch),
        Integer(flow.expires),
      ],
    )
    return flow.id
  }
  execute(self.db, "BEGIN IMMEDIATE", [])
  {
    errdefer execute(self.db, "ROLLBACK", [])
    execute(self.db, "UPDATE sessions SET epoch=epoch+1 WHERE id=?", [
      Text(session.id),
    ])
    execute(
      self.db,
      "INSERT INTO authorizations (session_id,id,target_id,epoch,phase,expires) VALUES (?,?,?,?,'starting',?)",
      [
        Text(session.id),
        Text(attempt),
        Text(attempt),
        Integer(session.epoch + 1),
        Integer(now() + 900),
      ],
    )
    execute(self.db, "COMMIT", [])
  }
  attempt
}

///|
fn App::cancel_device(
  self : App,
  session : Session,
  id : String,
) -> String raise {
  // Recheck after reading the HTTP body, which can yield to logout.
  guard self.session(session.id) is Some(current) else {
    raise RpcError(
      401, "authentication_required", "Session ended. Reload this page.",
    )
  }
  guard self.device(session.id, id) is Some(attempt) else {
    execute(
      self.db,
      "INSERT INTO authorizations (session_id,id,target_id,epoch,phase,expires) VALUES (?,?,?,?,'cancelled',?)",
      [
        Text(session.id),
        Text(id),
        Text(id),
        Integer(current.epoch),
        Integer(now() + 900),
      ],
    )
    return id
  }
  if self.device_current(session.id, attempt.target_id) is Some(flow) {
    execute(self.db, "BEGIN IMMEDIATE", [])
    errdefer execute(self.db, "ROLLBACK", [])
    self.end_device(flow, "cancelled", "This authorization was cancelled.")
    execute(
      self.db,
      "UPDATE sessions SET epoch=epoch+1 WHERE id=? AND epoch=?",
      [Text(session.id), Integer(flow.epoch)],
    )
    execute(self.db, "COMMIT", [])
  }
  attempt.target_id
}

///|
fn App::device_response(
  self : App,
  session_id : String,
  id : String,
  requested : String,
) -> @protocol.DeviceResponse raise {
  guard self.session(session_id) is Some(session) else {
    raise RpcError(
      401, "authentication_required", "Session ended. Reload this page.",
    )
  }
  let status = self.status(session)
  let status = if self.device(session_id, id) is Some(flow) {
    { ..status, device_flow: Some(flow.public_status()), }
  } else {
    status
  }
  { request_id: requested, status, }
}

///|
fn App::save_device(self : App, flow : DeviceFlow) -> Unit raise {
  guard self.device_current(flow.session_id, flow.id) is Some(_) else { return }
  execute(
    self.db,
    "UPDATE authorizations SET phase=?,credentials=?,user_code=?,verification_uri=?,expires=?,next_poll=?,interval=?,backoff=?,token_issued=?,message=? WHERE session_id=? AND id=?",
    [
      Text(flow.phase),
      Text(flow.credentials),
      Text(flow.user_code),
      Text(flow.verification_uri),
      Integer(flow.expires),
      Integer(flow.next_poll),
      Integer(flow.interval),
      Integer(flow.backoff),
      Integer(flow.token_issued),
      Text(flow.message),
      Text(flow.session_id),
      Text(flow.id),
    ],
  )
}
