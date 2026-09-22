///|
fn cookie_name(app : @storage.App) -> String {
  if app.config.secure {
    "__Host-moondiff"
  } else {
    "moondiff"
  }
}

///|
pub fn cookie(app : @storage.App, value : String) -> @http.Cookie {
  Cookie(
    cookie_name(app),
    value,
    path="/",
    max_age=@config.AUTHENTICATED_SESSION_LIFETIME,
    secure=app.config.secure,
    http_only=true,
    extensions=["SameSite=Lax"],
  )
}

///|
pub fn request_session(
  app : @storage.App,
  request : @http.Request,
) -> @storage.Session? raise {
  let cookies = request.headers.get("Cookie").unwrap_or("")
  for entry in cookies.split(";") {
    let parts = entry.trim().split("=").collect()
    if parts is [name, value] &&
      name == cookie_name(app) &&
      value.length() == 43 {
      return app.session(@crypto.digest(value.to_owned()))
    }
  }
  None
}

///|
pub fn csrf_check(
  app : @storage.App,
  request : @http.Request,
  session : @storage.Session?,
) -> @storage.Session raise {
  guard request.headers.get("Origin") == Some(app.config.public_url) &&
    session is Some(session) else {
    raise @common.RpcError(
      403, "csrf_failed", "The request origin or session is invalid. Reload this page.",
    )
  }
  let token = request.headers.get("X-CSRF-Token").unwrap_or("")
  guard @crypto.constant_time_equal(
    @utf8.encode(token),
    @utf8.encode(session.csrf),
  ) else {
    raise @common.RpcError(
      403, "csrf_failed", "The request token is invalid. Reload this page.",
    )
  }
  session
}

///|
pub fn status(
  app : @storage.App,
  session : @storage.Session?,
) -> @protocol.ApiAuthStatus raise {
  match session {
    None =>
      {
        authenticated: false,
        install_url: Some(app.config.install_url),
        csrf_token: None,
        login: None,
        user_id: None,
        device_flow: None,
      }
    Some(session) =>
      {
        authenticated: !session.tokens.is_empty(),
        install_url: Some(app.config.install_url),
        csrf_token: Some(session.csrf),
        login: if session.user.is_empty() {
          None
        } else {
          Some(session.login)
        },
        user_id: if session.user.is_empty() {
          None
        } else {
          Some(session.user)
        },
        device_flow: app
        .visible_device(session)
        .map(flow => flow.public_status()),
      }
  }
}

///|
pub fn device_response(
  app : @storage.App,
  session_id : String,
  id : String,
  requested : String,
) -> @protocol.DeviceResponse raise {
  guard app.session(session_id) is Some(session) else {
    raise @common.RpcError(
      401, "authentication_required", "Session ended. Reload this page.",
    )
  }
  let status = status(app, Some(session))
  let status = if app.device(session_id, id) is Some(flow) {
    { ..status, device_flow: Some(flow.public_status()), }
  } else {
    status
  }
  { request_id: requested, status, }
}
