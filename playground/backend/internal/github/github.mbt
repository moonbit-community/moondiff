///|
pub async fn upstream(
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
    let bytes = @httpio.read_bounded(client, limit, source~)
    (response, bytes)
  })
}

///|
fn github_error(response : @http.Response, body : Bytes) -> Error {
  let detail = @json.parse(@utf8.decode(body)) catch { _ => Json::null() }
  let message = @common.optional_string(detail, "message")
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
          "not_found_or_not_installed", "GitHub could not find this resource. For private repositories, sign in and install the GitHub @storage.App.",
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
  @common.RpcError(status, code, message)
}

///|
pub fn upstream_json(bytes : Bytes) -> Json raise {
  @json.parse(@utf8.decode(bytes)) catch {
    _ =>
      raise @common.RpcError(
        502, "invalid_github_response", "GitHub returned invalid JSON.",
      )
  }
}

///|
async fn oauth_token(
  app : @storage.App,
  parameters : Map[String, Json],
) -> Json {
  parameters["client_id"] = Json::string(app.config.client_id)
  let (response, bytes) = upstream(
    app.config.oauth_url,
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
  guard response.code == 200 &&
    @common.optional_string(payload, "error").is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "GitHub authorization failed. Sign in again.",
    )
  }
  payload
}

///|
async fn refresh_once(
  app : @storage.App,
  original : @storage.Session,
) -> @storage.Session {
  let payload = app.token_payload(original)
  let refresh = @common.optional_string(payload, "refresh_token")
  guard !refresh.is_empty() && original.refresh_expires > @storage.now() else {
    app.expire_auth(original)
    raise @common.RpcError(
      401, "authentication_required", "Your GitHub session expired. Sign in again.",
    )
  }
  let tokens = oauth_token(app, {
    "grant_type": "refresh_token",
    "refresh_token": Json::string(refresh),
  }) catch {
    @common.RpcError(401, _, _) as error => {
      app.expire_auth(original)
      raise error
    }
    error => raise error
  }
  app.install_tokens(original, original.user, original.login, tokens)
}

///|
pub async fn authenticated(
  app : @storage.App,
  original : @storage.Session,
  rejected_token? : String = "",
) -> @storage.Session {
  guard app.session(original.id) is Some(current) &&
    current.epoch == original.epoch &&
    !current.tokens.is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "Sign in to GitHub to continue.",
    )
  }
  let access = @common.optional_string(
    app.token_payload(current),
    "access_token",
  )
  if (rejected_token.is_empty() && current.access_expires > @storage.now() + 30) ||
    (!rejected_token.is_empty() && rejected_token != access) {
    return current
  }
  let key = "\{current.id}:\{current.epoch}"
  if app.refreshes.get(key) is Some(pending) {
    return pending.wait()
  }
  // The refresh owns its entry and survives cancellation of individual HTTP
  // waiters. A rotated refresh token must reach SQLite even if all tabs close.
  let pending = @async.Lazy(() => {
    @async.protect_from_cancel(() => {
      defer app.refreshes.remove(key)
      refresh_once(app, current)
    })
  })
  app.refreshes[key] = pending
  pending.wait()
}

///|
pub async fn github(
  app : @storage.App,
  session : @storage.Session?,
  path : String,
  meth? : @http.RequestMethod = Get,
  body? : Json,
  source? : Bool = false,
) -> (@http.Response, Bytes) {
  guard session is Some(session) && !session.tokens.is_empty() else {
    raise @common.RpcError(
      401, "authentication_required", "Sign in to GitHub to continue.",
    )
  }
  let current = authenticated(app, session)
  let token = @common.string(app.token_payload(current), "access_token")
  let (response, bytes) = upstream(
    app.config.api_url,
    path,
    meth,
    token,
    body,
    source~,
  )
  guard app.still_current(current) else {
    raise @common.RpcError(
      401, "authentication_required", "This session is no longer active.",
    )
  }
  if response.code == 401 {
    let refreshed = authenticated(app, current, rejected_token=token)
    let token = @common.string(app.token_payload(refreshed), "access_token")
    let (response, bytes) = upstream(
      app.config.api_url,
      path,
      meth,
      token,
      body,
      source~,
    )
    guard app.still_current(refreshed) else {
      raise @common.RpcError(
        401, "authentication_required", "This session is no longer active.",
      )
    }
    if response.code == 401 {
      app.expire_auth(refreshed)
    }
    guard response.code >= 200 && response.code < 300 else {
      raise github_error(response, bytes)
    }
    return (response, bytes)
  }
  guard response.code >= 200 && response.code < 300 else {
    raise github_error(response, bytes)
  }
  (response, bytes)
}

///|
pub async fn github_json(
  app : @storage.App,
  session : @storage.Session?,
  path : String,
  meth? : @http.RequestMethod = Get,
  body? : Json,
) -> Json {
  let (response, bytes) = github(app, session, path, meth~, body?)
  if response.code == 204 {
    Json::null()
  } else {
    @common.normalize(upstream_json(bytes))
  }
}

///|
pub async fn comments(
  app : @storage.App,
  session : @storage.Session?,
  path : String,
) -> Json {
  let result = []
  for page in 1..<=100 {
    let values = github_json(app, session, "\{path}?per_page=100&page=\{page}")
    guard values is Array(values) else {
      raise @common.RpcError(
        502, "invalid_github_response", "GitHub returned an invalid page.",
      )
    }
    for value in values {
      result.push(@common.comment_for_protocol(value))
    }
    if values.length() < 100 {
      return Json::array(result)
    }
  }
  raise @common.RpcError(
    422, "pagination_limit", "GitHub returned more comment pages than Moondiff can safely load.",
  )
}
