///|
async fn respond(
  conn : @http.ServerConnection,
  status : Int,
  body : Bytes,
  content_type? : String = "application/json; charset=utf-8",
  headers? : @http.Headers = {},
  cookies? : Array[@http.Cookie] = [],
  head? : Bool = false,
) -> Unit {
  headers["Content-Type"] = content_type
  headers["Content-Length"] = body.length().to_string()
  headers["Cache-Control"] = "no-store"
  headers["X-Content-Type-Options"] = "nosniff"
  headers["Referrer-Policy"] = "no-referrer"
  headers["X-Frame-Options"] = "DENY"
  conn.send_response(
    status,
    if status < 400 {
      "OK"
    } else {
      "Error"
    },
    extra_headers=headers,
    cookies~,
  )
  if !head {
    conn.write(body)
  }
  conn.end_response()
}

///|
async fn[T : ToJson] respond_json(
  conn : @http.ServerConnection,
  value : T,
  cookies? : Array[@http.Cookie] = [],
) -> Unit {
  let body = (@protocol.Response::Success(value~) : @protocol.Response[T]).to_json()
  respond(conn, 200, @utf8.encode(body.stringify()), cookies~)
}

///|
async fn App::static_file(
  self : App,
  request : @http.Request,
  conn : @http.ServerConnection,
  raw_path : String,
) -> Unit {
  let path = decode_component(raw_path)
  guard path.has_prefix("/") && (path == "/" || valid_path(path[1:].to_owned())) else {
    raise RpcError(404, "not_found", "Page not found.")
  }
  let name = if path == "/" || change_path(path) { "/index.html" } else { path }
  // Canonicalize both paths before opening, including any symlink components.
  let root = self.config.static_dir
  let full = @fs.realpath(root + name) catch {
    _ => raise RpcError(404, "not_found", "Page not found.")
  }
  guard full.has_prefix(root + "/") && @fs.kind(full) == Regular else {
    raise RpcError(404, "not_found", "Page not found.")
  }
  let file = @fs.open(full, mode=ReadOnly)
  defer file.close()
  let content_type = match name {
    [.., .. ".html"] => "text/html; charset=utf-8"
    [.., .. ".css"] => "text/css; charset=utf-8"
    [.., .. ".js"] | [.., .. ".mjs"] => "text/javascript; charset=utf-8"
    [.., .. ".svg"] => "image/svg+xml"
    [.., .. ".png"] => "image/png"
    [.., .. ".wasm"] => "application/wasm"
    _ => "application/octet-stream"
  }
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": content_type,
    "Content-Length": file.size().to_string(),
    "Cache-Control": "no-cache",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https://avatars.githubusercontent.com data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
  })
  if request.meth != Head {
    conn.write_reader(file)
  }
  conn.end_response()
}

///|
async fn App::handle(
  self : App,
  request : @http.Request,
  reader : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let path = request.path.split("?").next().unwrap_or("").to_owned()
  if request.meth == Get && path == "/healthz" {
    respond(conn, 200, b"ok\n", content_type="text/plain")
    return
  }
  if request.meth == Get && path == "/api/auth/status" {
    let (cookies, session) = match self.request_session(request) {
      Some(s) => ([], s)
      None => {
        let (cookie, s) = self.create_session()
        ([self.cookie(cookie)], s)
      }
    }
    let current = if !session.tokens.is_empty() {
      self.authenticated(session) catch {
        error => {
          guard error is RpcError(401, _, _) || error is InvalidCiphertext else {
            raise error
          }
          self.expire_auth(session)
          guard self.session(session.id) is Some(current) else {
            raise RpcError(401, "authentication_required", "Session ended.")
          }
          current
        }
      }
    } else {
      session
    }
    respond_json(conn, self.status(current), cookies~)
    return
  }
  let session = self.request_session(request)
  if path == "/auth/login" || path == "/auth/callback" {
    raise RpcError(404, "not_found", "Page not found.")
  }
  if request.meth == Post &&
    [
      "/api/auth/device/start", "/api/auth/device/poll", "/api/auth/device/cancel",
    ].contains(path) {
    let session = self.csrf_check(request, session)
    guard request.headers
      .get("Content-Type")
      .unwrap_or("")
      .has_prefix("application/json") else {
      raise RpcError(415, "invalid_arguments", "Expected application/json.")
    }
    let bytes = read_bounded(reader, 1024)
    let value = @json.parse(@utf8.decode(bytes)) catch {
      _ => raise RpcError(400, "invalid_arguments", "Invalid JSON request.")
    }
    let id = if path.has_suffix("/start") {
      let args : @protocol.DeviceStart = @protocol.decode(value) catch {
        _ => raise RpcError(400, "invalid_arguments", "Invalid device request.")
      }
      args.attempt_id
    } else {
      let args : @protocol.DeviceAuthorization = @protocol.decode(value) catch {
        _ => raise RpcError(400, "invalid_arguments", "Invalid device request.")
      }
      args.authorization_id
    }
    guard valid_attempt_id(id) else {
      raise RpcError(
        400, "invalid_arguments", "Invalid authorization identifier.",
      )
    }
    let flow_id = if path.has_suffix("/start") {
      self.begin_device(session, id)
    } else if path.has_suffix("/cancel") {
      self.cancel_device(session, id)
    } else {
      guard self.device(session.id, id) is Some(flow) && flow.target_id == id else {
        raise RpcError(
          404, "authorization_not_found", "This authorization does not belong to this session.",
        )
      }
      id
    }
    if !path.has_suffix("/cancel") {
      self.advance_device(session.id, flow_id)
    }
    respond_json(conn, self.device_response(session.id, flow_id, id))
    return
  }
  if request.meth == Post && path == "/api/auth/logout" {
    let session = self.csrf_check(request, session)
    self.logout(session)
    // Do not issue another cookie here: a late logout response cannot replace a
    // newer session. The next explicit status request creates the anonymous one.
    respond_json(conn, ())
    return
  }
  if request.meth == Post && path == "/api/rpc" {
    guard request.headers
      .get("Content-Type")
      .unwrap_or("")
      .has_prefix("application/json") else {
      raise RpcError(415, "invalid_arguments", "Expected application/json.")
    }
    let bytes = read_bounded(reader, 131072)
    let value = @json.parse(@utf8.decode(bytes)) catch {
      _ => raise RpcError(400, "invalid_arguments", "Invalid JSON request.")
    }
    let rpc = @protocol.decode_request(value) catch {
      @protocol.ProtocolError(code, message) =>
        raise RpcError(400, code, message)
      _ => raise RpcError(400, "invalid_arguments", "Invalid RPC request.")
    }
    if rpc.is_write() {
      ignore(self.csrf_check(request, session))
    }
    respond_json(conn, self.rpc(session, rpc))
    return
  }
  guard request.meth == Get || request.meth == Head else {
    raise RpcError(405, "method_not_allowed", "Method not allowed.")
  }
  self.static_file(request, conn, path)
}

///|
/// Run the configured single-process HTTP server.
pub async fn run() -> Unit {
  let config = Config::load()
  let config = { ..config, static_dir: @fs.realpath(config.static_dir), }
  // Hold a process lock for the lifetime of the server. Refresh coalescing is
  // deliberately in-process; sharing a database between servers is unsupported.
  let lock = @fs.open(
    config.database + ".lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  guard lock.try_lock(Exclusive) else {
    fail("Another server is using this database")
  }
  let database_file = @fs.open(
    config.database,
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  database_file.close()
  @fs.chmod(config.database, 0o600)
  let app = App::open(config) catch {
    @sqlite3.SqliteError(code~, msg~, ..) =>
      fail("SQLite initialization failed (\{code.to_repr()}): \{msg}")
    error => raise error
  }
  defer app.db.close()
  @fs.chmod(config.database, 0o600)
  let server = @http.Server(@socket.Addr::parse(config.listen), reuse_addr=true)
  defer server.close()
  println("Moondiff listening on \{server.addr}")
  server.run_forever(allow_failure=true, max_connections=128) <| ((
    request,
    reader,
    conn,
  ) => {
    @async.with_timeout(60000, () => app.handle(request, reader, conn)) catch {
      error => {
        if @async.is_being_cancelled() {
          raise error
        }
        let (status, body) = rpc_error(error)
        respond(
          conn,
          status,
          @utf8.encode(body.stringify()),
          head=request.meth == Head,
        )
      }
    }
  })
}
