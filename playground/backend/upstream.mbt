///|
async fn read_bounded(
  reader : &@io.Reader,
  limit : Int,
  source? : Bool = false,
) -> Bytes {
  let out = @buffer.Buffer()
  while reader.read_some(max_len=65536) is Some(bytes) {
    out.write_bytes(bytes)
    guard out.length() <= limit else {
      raise RpcError(
        413,
        if source {
          "source_too_large"
        } else {
          "response_too_large"
        },
        if source {
          "Cannot render: one side is larger than 1 MiB."
        } else {
          "Request or response exceeds the size limit."
        },
      )
    }
  }
  out.to_bytes()
}

///|
async fn upstream(
  base : String,
  path : String,
  meth : @http.RequestMethod,
  token : String,
  body : Json?,
  source? : Bool = false,
  accept? : String = "",
) -> (@http.Response, Bytes) {
  @async.with_timeout(30000, () => {
    let headers : @http.Headers = {
      "Accept": if !accept.is_empty() {
        accept
      } else if source {
        "application/vnd.github.raw+json"
      } else {
        "application/vnd.github+json"
      },
      "X-GitHub-Api-Version": "2026-03-10",
      "User-Agent": "moondiff",
    }
    if !token.is_empty() {
      headers["Authorization"] = "Bearer " + token
    }
    let client = @http.Client(base)
    defer client.close()
    let bytes = match body {
      Some(json) => @utf8.encode(json.stringify())
      None => b""
    }
    if body is Some(_) {
      headers["Content-Type"] = "application/json"
      headers["Content-Length"] = bytes.length().to_string()
    }
    client.request(meth, path, extra_headers=headers)
    if body is Some(_) {
      client.write(bytes)
    }
    let response = client.end_request()
    let limit = if source { 1048576 } else { 8388608 }
    let bytes = read_bounded(client, limit, source~)
    (response, bytes)
  })
}

///|
fn github_error(response : @http.Response, body : Bytes) -> Error {
  let detail = @json.parse(@utf8.decode(body)) catch { _ => Json::null() }
  let message = optional_string(detail, "message")
  let status = response.code
  let (code, message) = if status == 429 ||
    (
      status == 403 &&
      (
        response.headers.get("X-RateLimit-Remaining") == Some("0") ||
        response.headers.contains("Retry-After")
      )
    ) {
    (
      "rate_limit", "GitHub API rate limit exceeded. Sign in or try again after the reset time.",
    )
  } else {
    match status {
      401 =>
        (
          "authentication_required", "Your GitHub session expired. Sign in again.",
        )
      403 => ("permission_denied", message)
      404 =>
        (
          "not_found_or_not_installed", "GitHub could not find this resource. For private repositories, sign in and install the GitHub App.",
        )
      422 => ("invalid_comment_anchor", message)
      _ =>
        (
          "github_http_\{status}",
          if message.is_empty() {
            "GitHub request failed."
          } else {
            message
          },
        )
    }
  }
  RpcError(status, code, message)
}

///|
fn upstream_json(bytes : Bytes) -> Json raise {
  @json.parse(@utf8.decode(bytes)) catch {
    _ =>
      raise RpcError(
        502, "invalid_github_response", "GitHub returned invalid JSON.",
      )
  }
}

///|
async fn App::oauth_token(self : App, parameters : Map[String, Json]) -> Json {
  parameters["client_id"] = Json::string(self.config.client_id)
  let (response, bytes) = upstream(
    self.config.oauth_url,
    "/login/oauth/access_token",
    Post,
    "",
    Some(Json::object(parameters)),
    accept="application/json",
  )
  // A transient OAuth outage or rate limit must not erase a usable refresh
  // token. Only a rejected authorization should expire the local credentials.
  if response.code >= 500 || response.code == 429 || response.code == 403 {
    raise github_error(response, bytes)
  }
  let payload = upstream_json(bytes)
  guard response.code == 200 && optional_string(payload, "error").is_empty() else {
    raise RpcError(
      401, "authentication_required", "GitHub authorization failed. Sign in again.",
    )
  }
  payload
}

///|
async fn App::refresh_once(self : App, original : Session) -> Session {
  let payload = self.token_payload(original)
  let refresh = optional_string(payload, "refresh_token")
  guard !refresh.is_empty() && original.refresh_expires > now() else {
    self.expire_auth(original)
    raise RpcError(
      401, "authentication_required", "Your GitHub session expired. Sign in again.",
    )
  }
  let tokens = self.oauth_token({
    "grant_type": "refresh_token",
    "refresh_token": Json::string(refresh),
  }) catch {
    RpcError(401, _, _) as error => {
      self.expire_auth(original)
      raise error
    }
    error => raise error
  }
  self.install_tokens(original, original.user, original.login, tokens)
}

///|
fn App::expire_auth(self : App, session : Session) -> Unit raise {
  execute(
    self.db,
    "UPDATE sessions SET tokens='',epoch=epoch+1 WHERE id=? AND epoch=?",
    [Text(session.id), Integer(session.epoch)],
  )
}

///|
async fn App::authenticated(
  self : App,
  original : Session,
  rejected_token? : String = "",
) -> Session {
  guard self.session(original.id) is Some(current) &&
    current.epoch == original.epoch &&
    !current.tokens.is_empty() else {
    raise RpcError(
      401, "authentication_required", "Sign in to GitHub to continue.",
    )
  }
  let access = optional_string(self.token_payload(current), "access_token")
  if (rejected_token.is_empty() && current.access_expires > now() + 30) ||
    (!rejected_token.is_empty() && rejected_token != access) {
    return current
  }
  let key = "\{current.id}:\{current.epoch}"
  if self.refreshes.get(key) is Some(pending) {
    return pending.wait()
  }
  // The refresh owns its entry and survives cancellation of individual HTTP
  // waiters. A rotated refresh token must reach SQLite even if all tabs close.
  let pending = @async.Lazy(() => {
    @async.protect_from_cancel(() => {
      defer self.refreshes.remove(key)
      self.refresh_once(current)
    })
  })
  self.refreshes[key] = pending
  pending.wait()
}

///|
async fn App::github(
  self : App,
  session : Session?,
  path : String,
  meth? : @http.RequestMethod = Get,
  body? : Json,
  source? : Bool = false,
) -> (@http.Response, Bytes) {
  let current = match session {
    Some(session) if !session.tokens.is_empty() =>
      Some(self.authenticated(session))
    _ => None
  }
  guard meth == Get || current is Some(_) else {
    raise RpcError(
      401, "authentication_required", "Sign in to GitHub to comment.",
    )
  }
  let token = match current {
    Some(s) => string(self.token_payload(s), "access_token")
    None => ""
  }
  let (response, bytes) = upstream(
    self.config.api_url,
    path,
    meth,
    token,
    body,
    source~,
  )
  if current is Some(s) {
    guard self.still_current(s) else {
      raise RpcError(
        401, "authentication_required", "This session is no longer active.",
      )
    }
    if response.code == 401 {
      let refreshed = self.authenticated(s, rejected_token=token)
      let token = string(self.token_payload(refreshed), "access_token")
      let (response, bytes) = upstream(
        self.config.api_url,
        path,
        meth,
        token,
        body,
        source~,
      )
      guard self.still_current(refreshed) else {
        raise RpcError(
          401, "authentication_required", "This session is no longer active.",
        )
      }
      if response.code == 401 {
        self.expire_auth(refreshed)
      }
      guard response.code >= 200 && response.code < 300 else {
        raise github_error(response, bytes)
      }
      return (response, bytes)
    }
  }
  guard response.code >= 200 && response.code < 300 else {
    raise github_error(response, bytes)
  }
  (response, bytes)
}

///|
async fn App::github_json(
  self : App,
  session : Session?,
  path : String,
  meth? : @http.RequestMethod = Get,
  body? : Json,
) -> Json {
  let (response, bytes) = self.github(session, path, meth~, body?)
  if response.code == 204 {
    Json::null()
  } else {
    normalize(upstream_json(bytes))
  }
}

///|
async fn App::comments(self : App, session : Session?, path : String) -> Json {
  let result = []
  for page in 1..<=100 {
    let values = self.github_json(session, "\{path}?per_page=100&page=\{page}")
    guard values is Array(values) else {
      raise RpcError(
        502, "invalid_github_response", "GitHub returned an invalid page.",
      )
    }
    for value in values {
      result.push(comment_for_protocol(value))
    }
    if values.length() < 100 {
      return Json::array(result)
    }
  }
  raise RpcError(
    422, "pagination_limit", "GitHub returned more comment pages than Moondiff can safely load.",
  )
}
