///|
fn App::cookie_name(self : App) -> String {
  if self.config.secure {
    "__Host-moondiff"
  } else {
    "moondiff"
  }
}

///|
fn App::cookie(self : App, value : String) -> @http.Cookie {
  @http.Cookie(
    self.cookie_name(),
    value,
    path="/",
    max_age=2592000,
    secure=self.config.secure,
    http_only=true,
    extensions=["SameSite=Lax"],
  )
}

///|
fn App::request_session(self : App, request : @http.Request) -> Session? raise {
  let cookies = request.headers.get("Cookie").unwrap_or("")
  for entry in cookies.split(";") {
    let parts = entry.trim().split("=").collect()
    if parts is [name, value] &&
      name == self.cookie_name() &&
      value.length() == 43 {
      return self.session(digest(value.to_owned()))
    }
  }
  None
}

///|
fn App::csrf_check(
  self : App,
  request : @http.Request,
  session : Session?,
) -> Session raise {
  guard request.headers.get("Origin") == Some(self.config.public_url) &&
    session is Some(session) else {
    raise RpcError(
      403, "csrf_failed", "The request origin or session is invalid. Reload this page.",
    )
  }
  let token = request.headers.get("X-CSRF-Token").unwrap_or("")
  guard constant_time_equal(@utf8.encode(token), @utf8.encode(session.csrf)) else {
    raise RpcError(
      403, "csrf_failed", "The request token is invalid. Reload this page.",
    )
  }
  session
}

///|
fn App::status(self : App, session : Session) -> @protocol.ApiAuthStatus raise {
  {
    authenticated: !session.tokens.is_empty(),
    install_url: Some(self.config.install_url),
    csrf_token: session.csrf,
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
    device_flow: self.visible_device(session).map(flow => flow.public_status()),
  }
}
