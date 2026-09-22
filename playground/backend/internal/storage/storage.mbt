///|
pub(all) struct Session {
  id : String
  csrf : String
  expires : Int64
  epoch : Int64
  user : String
  login : String
  tokens : String
  access_expires : Int64
  refresh_expires : Int64
}

///|
pub(all) struct App {
  config : @config.Config
  db : @sqlite3.Connection
  refreshes : Map[String, @async.Lazy[Session]]
  devices : Map[String, @async.Lazy[Unit]]
  viewed_scopes : Map[String, ViewedCoordinator]
}

///|
pub fn now() -> Int64 {
  @env.now().reinterpret_as_int64() / 1000
}

///|
fn execute(
  db : @sqlite3.Connection,
  sql : String,
  params : Array[@sqlite3.Value],
) -> Unit raise {
  let stmt = db.prepare(sql)
  defer stmt.finalize()
  for index, value in params {
    stmt.bind(index=index + 1, value)
  }
  while stmt.step() {
    ()
  }
}

///|
#cfg(target="native")
fn database_settings() -> Array[String] {
  [DB_ENABLE_WAL, DB_ENABLE_FOREIGN_KEYS, DB_SET_BUSY_TIMEOUT]
}

///|
#cfg(target="wasm")
fn database_settings() -> Array[String] {
  // moonrun's SQLite host rejects PRAGMA configuration. Use the existing
  // journal mode (the SQLite default for a new file) and portable triggers.
  []
}

///|
pub fn App::open(config : @config.Config) -> App raise {
  let db = @sqlite3.Connection::open(config.database)
  errdefer db.close()
  for sql in database_settings() {
    execute(db, sql, [])
  }
  for
    sql in [
      DB_CREATE_METADATA,
      DB_CREATE_SESSIONS,
      DB_CREATE_AUTHORIZATIONS,
      DB_CREATE_ONE_ACTIVE_DEVICE_INDEX,
      DB_CREATE_AUTHORIZATION_SESSION_INSERT_TRIGGER,
      DB_CREATE_AUTHORIZATION_SESSION_UPDATE_TRIGGER,
      DB_CREATE_SESSION_AUTHORIZATION_PARENT_TRIGGER,
      DB_CREATE_SESSION_DELETE_AUTHORIZATIONS_TRIGGER,
    ] {
    execute(db, sql, [])
  }
  let stmt = db.prepare(QUERY_KEY_CHECK)
  defer stmt.finalize()
  if stmt.step() {
    let stored : String = stmt.column(index=0)
    guard @crypto.unseal(config.key, "database", "key-check", stored) ==
      b"moondiff-v1" else {
      fail("Database key check failed")
    }
  } else {
    execute(db, DB_INSERT_KEY_CHECK, [
      Text(@crypto.seal(config.key, "database", "key-check", b"moondiff-v1")),
    ])
  }
  { config, db, refreshes: {}, devices: {}, viewed_scopes: {}, }
}

///|
pub fn App::session(self : App, id : String) -> Session? raise {
  let stmt = self.db.prepare(QUERY_SESSION)
  defer stmt.finalize()
  stmt.bind(index=1, id)
  stmt.bind(index=2, now())
  guard stmt.step() else { return None }
  Some({
    id,
    csrf: stmt.column(index=0),
    expires: stmt.column(index=1),
    epoch: stmt.column(index=2),
    user: stmt.column(index=3),
    login: stmt.column(index=4),
    tokens: stmt.column(index=5),
    access_expires: stmt.column(index=6),
    refresh_expires: stmt.column(index=7),
  })
}

///|
pub fn App::create_session(self : App) -> (String, Session) raise {
  let cookie = @crypto.random_id()
  let id = @crypto.digest(cookie)
  execute(self.db, DB_BEGIN_IMMEDIATE, [])
  {
    errdefer execute(self.db, DB_ROLLBACK, [])
    let timestamp = now()
    execute(self.db, DB_DELETE_EXPIRED_SESSIONS, [Integer(timestamp)])
    execute(self.db, DB_DELETE_EXPIRED_AUTHORIZATIONS, [Integer(timestamp)])
    let stmt = self.db.prepare(QUERY_ANONYMOUS_SESSION_COUNT)
    stmt.bind(index=1, timestamp)
    ignore(stmt.step())
    let count : Int64 = stmt.column(index=0)
    stmt.finalize()
    guard count < self.config.anonymous_session_limit.to_int64() else {
      raise @common.RpcError(
        429, "session_limit", "Too many sign-in sessions are active. Try again later.",
      )
    }
    execute(self.db, DB_INSERT_SESSION, [
      Text(id),
      Text(@crypto.random_id()),
      Integer(timestamp + @config.ANONYMOUS_SESSION_LIFETIME),
    ])
    execute(self.db, DB_COMMIT, [])
  }
  (cookie, self.session(id).unwrap())
}

///|
pub fn App::still_current(self : App, session : Session) -> Bool raise {
  self.session(session.id) is Some(current) && current.epoch == session.epoch
}

///|
pub fn App::logout(self : App, session : Session) -> Unit raise {
  // Cascading deletion also consumes every pending authorization. No async gap.
  execute(self.db, DB_DELETE_SESSION, [Text(session.id)])
}

///|
pub fn App::expire_auth(self : App, session : Session) -> Unit raise {
  execute(self.db, DB_EXPIRE_SESSION_AUTH, [
    Integer(now() + @config.ANONYMOUS_SESSION_LIFETIME),
    Text(session.id),
    Integer(session.epoch),
  ])
}

///|
pub fn App::token_payload(self : App, session : Session) -> Json raise {
  @json.parse(
    @utf8.decode(
      @crypto.unseal(self.config.key, session.id, session.user, session.tokens),
    ),
  )
}

///|
pub fn App::install_tokens(
  self : App,
  session : Session,
  user : String,
  login : String,
  payload : Json,
  issued_at? : Int64 = now(),
  device_id? : String = "",
) -> Session raise {
  let access = @common.optional_string(payload, "access_token")
  guard !access.is_empty() else {
    raise @common.RpcError(
      502, "invalid_github_response", "GitHub did not return an access token.",
    )
  }
  let access_expires = if @common.field(payload, "expires_in") is Number(n, ..) &&
    n > 0 &&
    n <= 31536000 {
    issued_at + n.to_int64()
  } else {
    Int64::max(
      session.expires,
      issued_at + @config.AUTHENTICATED_SESSION_LIFETIME,
    )
  }
  let refresh_expires = if @common.field(payload, "refresh_token_expires_in")
    is Number(n, ..) &&
    n > 0 &&
    n <= 31536000 {
    issued_at + n.to_int64()
  } else {
    0L
  }
  let tokens : Json = {
    "access_token": access,
    "refresh_token": @common.optional_string(payload, "refresh_token"),
  }
  let encrypted = @crypto.seal(
    self.config.key,
    session.id,
    user,
    @utf8.encode(tokens.stringify()),
  )
  execute(self.db, DB_BEGIN_IMMEDIATE, [])
  {
    errdefer execute(self.db, DB_ROLLBACK, [])
    if !device_id.is_empty() {
      guard self.device_current(session.id, device_id) is Some(flow) &&
        flow.phase == "verifying" &&
        flow.epoch == session.epoch else {
        raise @common.RpcError(
          409, "authorization_ended", "This authorization is no longer active.",
        )
      }
    }
    execute(self.db, DB_INSTALL_SESSION_TOKENS, [
      Text(user),
      Text(login),
      Text(encrypted),
      Integer(access_expires),
      Integer(refresh_expires),
      Integer(if device_id.is_empty() { 0 } else { 1 }),
      Integer(now() + @config.AUTHENTICATED_SESSION_LIFETIME),
      Text(session.id),
      Integer(session.epoch),
      Integer(now()),
    ])
    guard self.db.changes() == 1 else {
      raise @common.RpcError(
        401, "authentication_required", "This session is no longer active.",
      )
    }
    if !device_id.is_empty() {
      execute(self.db, DB_COMPLETE_AUTHORIZATION, [
        Text(session.id),
        Text(device_id),
      ])
    }
    execute(self.db, DB_COMMIT, [])
  }
  self.session(session.id).unwrap()
}
