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
  [
    "PRAGMA journal_mode=WAL", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000",
  ]
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
      "CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT NOT NULL)",
      "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, csrf TEXT NOT NULL, expires INTEGER NOT NULL, epoch INTEGER NOT NULL DEFAULT 0, user_id TEXT NOT NULL DEFAULT '', login TEXT NOT NULL DEFAULT '', tokens TEXT NOT NULL DEFAULT '', access_expires INTEGER NOT NULL DEFAULT 0, refresh_expires INTEGER NOT NULL DEFAULT 0)",
      "CREATE TABLE IF NOT EXISTS authorizations (session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, id TEXT NOT NULL, target_id TEXT NOT NULL, epoch INTEGER NOT NULL, phase TEXT NOT NULL, credentials TEXT NOT NULL DEFAULT '', user_code TEXT NOT NULL DEFAULT '', verification_uri TEXT NOT NULL DEFAULT '', expires INTEGER NOT NULL, next_poll INTEGER NOT NULL DEFAULT 0, interval INTEGER NOT NULL DEFAULT 5, backoff INTEGER NOT NULL DEFAULT 0, token_issued INTEGER NOT NULL DEFAULT 0, message TEXT NOT NULL DEFAULT '', PRIMARY KEY (session_id,id))",
      "CREATE UNIQUE INDEX IF NOT EXISTS one_active_device ON authorizations(session_id) WHERE phase IN ('starting','pending','verifying')",
      // Preserve the foreign-key contract even when the host does not let us
      // enable foreign_keys. These also apply to databases created by Native.
       "CREATE TRIGGER IF NOT EXISTS authorizations_require_session_insert BEFORE INSERT ON authorizations WHEN NOT EXISTS (SELECT 1 FROM sessions WHERE id=NEW.session_id) BEGIN SELECT RAISE(ABORT, 'authorization session is missing'); END",
      "CREATE TRIGGER IF NOT EXISTS authorizations_require_session_update BEFORE UPDATE OF session_id ON authorizations WHEN NOT EXISTS (SELECT 1 FROM sessions WHERE id=NEW.session_id) BEGIN SELECT RAISE(ABORT, 'authorization session is missing'); END",
      "CREATE TRIGGER IF NOT EXISTS sessions_preserve_authorization_parent BEFORE UPDATE OF id ON sessions WHEN NEW.id IS NOT OLD.id AND EXISTS (SELECT 1 FROM authorizations WHERE session_id=OLD.id) BEGIN SELECT RAISE(ABORT, 'session has a pending authorization'); END",
      "CREATE TRIGGER IF NOT EXISTS sessions_delete_authorizations AFTER DELETE ON sessions BEGIN DELETE FROM authorizations WHERE session_id=OLD.id; END",
    ] {
    execute(db, sql, [])
  }
  let stmt = db.prepare("SELECT value FROM metadata WHERE name='key-check-v1'")
  defer stmt.finalize()
  if stmt.step() {
    let stored : String = stmt.column(index=0)
    guard unseal(config.key, "database", "key-check", stored) == b"moondiff-v1" else {
      fail("Database key check failed")
    }
  } else {
    execute(db, "INSERT INTO metadata VALUES ('key-check-v1', ?)", [
      Text(seal(config.key, "database", "key-check", b"moondiff-v1")),
    ])
  }
  { config, db, refreshes: {}, devices: {}, }
}

///|
fn App::session(self : App, id : String) -> Session? raise {
  let stmt = self.db.prepare(
    "SELECT csrf, expires, epoch, user_id, login, tokens, access_expires, refresh_expires FROM sessions WHERE id=? AND expires>?",
  )
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
  execute(self.db, "DELETE FROM sessions WHERE expires<=?", [Integer(now())])
  execute(self.db, "DELETE FROM authorizations WHERE expires<=?", [
    Integer(now()),
  ])
  execute(self.db, "INSERT INTO sessions (id,csrf,expires) VALUES (?,?,?)", [
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
  execute(self.db, "DELETE FROM sessions WHERE id=?", [Text(session.id)])
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
  execute(self.db, "BEGIN IMMEDIATE", [])
  {
    errdefer execute(self.db, "ROLLBACK", [])
    if !device_id.is_empty() {
      guard self.device_current(session.id, device_id) is Some(flow) &&
        flow.phase == "verifying" &&
        flow.epoch == session.epoch else {
        raise RpcError(
          409, "authorization_ended", "This authorization is no longer active.",
        )
      }
    }
    execute(
      self.db,
      "UPDATE sessions SET user_id=?,login=?,tokens=?,access_expires=?,refresh_expires=?,epoch=epoch+? WHERE id=? AND epoch=? AND expires>?",
      [
        Text(user),
        Text(login),
        Text(encrypted),
        Integer(access_expires),
        Integer(refresh_expires),
        Integer(if device_id.is_empty() { 0 } else { 1 }),
        Text(session.id),
        Integer(session.epoch),
        Integer(now()),
      ],
    )
    guard self.db.changes() == 1 else {
      raise RpcError(
        401, "authentication_required", "This session is no longer active.",
      )
    }
    if !device_id.is_empty() {
      execute(
        self.db,
        "UPDATE authorizations SET phase='completed',credentials='',message='' WHERE session_id=? AND id=?",
        [Text(session.id), Text(device_id)],
      )
    }
    execute(self.db, "COMMIT", [])
  }
  self.session(session.id).unwrap()
}
