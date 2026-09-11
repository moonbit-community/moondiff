///|
priv struct Session {
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
priv struct App {
  config : Config
  db : @sqlite3.Connection
  refreshes : Map[String, @async.Lazy[Session]]
  devices : Map[String, @async.Lazy[Unit]]
  viewed_scopes : Map[String, ViewedCoordinator]
}

///|
fn now() -> Int64 {
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
fn App::open(config : Config) -> App raise {
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
    guard unseal(config.key, "database", "key-check", stored) == b"moondiff-v1" else {
      fail("Database key check failed")
    }
  } else {
    execute(db, DB_INSERT_KEY_CHECK, [
      Text(seal(config.key, "database", "key-check", b"moondiff-v1")),
    ])
  }
  { config, db, refreshes: {}, devices: {}, viewed_scopes: {}, }
}

///|
fn App::session(self : App, id : String) -> Session? raise {
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
fn App::create_session(self : App) -> (String, Session) raise {
  let cookie = random_id()
  let id = digest(cookie)
  execute(self.db, DB_DELETE_EXPIRED_SESSIONS, [Integer(now())])
  execute(self.db, DB_DELETE_EXPIRED_AUTHORIZATIONS, [Integer(now())])
  execute(self.db, DB_INSERT_SESSION, [
    Text(id),
    Text(random_id()),
    Integer(now() + 30L * 86400),
  ])
  (cookie, self.session(id).unwrap())
}

///|
fn App::still_current(self : App, session : Session) -> Bool raise {
  self.session(session.id) is Some(current) && current.epoch == session.epoch
}

///|
fn App::logout(self : App, session : Session) -> Unit raise {
  // Cascading deletion also consumes every pending authorization. No async gap.
  execute(self.db, DB_DELETE_SESSION, [Text(session.id)])
}

///|
fn App::token_payload(self : App, session : Session) -> Json raise {
  @json.parse(
    @utf8.decode(
      unseal(self.config.key, session.id, session.user, session.tokens),
    ),
  )
}

///|
fn App::install_tokens(
  self : App,
  session : Session,
  user : String,
  login : String,
  payload : Json,
  issued_at? : Int64 = now(),
  device_id? : String = "",
) -> Session raise {
  let access = optional_string(payload, "access_token")
  guard !access.is_empty() else {
    raise RpcError(
      502, "invalid_github_response", "GitHub did not return an access token.",
    )
  }
  let access_expires = if field(payload, "expires_in") is Number(n, ..) &&
    n > 0 &&
    n <= 31536000 {
    issued_at + n.to_int64()
  } else {
    session.expires
  }
  let refresh_expires = if field(payload, "refresh_token_expires_in")
    is Number(n, ..) &&
    n > 0 &&
    n <= 31536000 {
    issued_at + n.to_int64()
  } else {
    0L
  }
  let tokens : Json = {
    "access_token": access,
    "refresh_token": optional_string(payload, "refresh_token"),
  }
  let encrypted = seal(
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
        raise RpcError(
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
      Text(session.id),
      Integer(session.epoch),
      Integer(now()),
    ])
    guard self.db.changes() == 1 else {
      raise RpcError(
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
