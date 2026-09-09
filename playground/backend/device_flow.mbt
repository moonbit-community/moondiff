///|
priv suberror DeviceRetry {
  DeviceRetry(Int64)
}

///|
fn retry_seconds(response : @http.Response) -> Int64 {
  let value = response.headers.get("Retry-After").unwrap_or("")
  if decimal(value) && value.length() <= 8 {
    let seconds : Int = @json.from_json(@json.parse(value)) catch { _ => 0 }
    seconds.to_int64()
  } else {
    0L
  }
}

///|
async fn device_upstream(
  base : String,
  path : String,
  token : String,
  body : Json?,
) -> Json {
  let (response, bytes) = upstream(
    base,
    path,
    if body is Some(_) {
      Post
    } else {
      Get
    },
    token,
    body,
    accept="application/json",
  ) catch {
    RpcError(_, _, _) as error => raise error
    _ => raise DeviceRetry(0)
  }
  if response.code >= 500 ||
    response.code == 429 ||
    (
      response.code == 403 &&
      (
        response.headers.contains("Retry-After") ||
        response.headers.get("X-RateLimit-Remaining") == Some("0")
      )
    ) {
    raise DeviceRetry(retry_seconds(response))
  }
  let payload = upstream_json(bytes)
  if !optional_string(payload, "error").is_empty() {
    return payload
  }
  guard response.code == 200 else {
    raise RpcError(
      502, "device_authorization_failed", "GitHub rejected device authorization. Check the GitHub App configuration and try again.",
    )
  }
  payload
}

///|
fn App::device_error(
  self : App,
  flow : DeviceFlow,
  payload : Json,
) -> Bool raise {
  let error = optional_string(payload, "error")
  if error.is_empty() {
    return false
  }
  match error {
    "authorization_pending" if flow.phase == "pending" =>
      self.save_device({
        ..flow,
        backoff: 0,
        message: "",
        next_poll: now_ms() + flow.interval * 1000,
      })
    "slow_down" if flow.phase == "pending" => {
      let returned = if field(payload, "interval") is Number(n, ..) &&
        n >= 1 &&
        n <= 86400 {
        n.to_int64()
      } else {
        0L
      }
      let interval = Int64::max(flow.interval + 5, returned)
      self.save_device({
        ..flow,
        interval,
        backoff: 0,
        next_poll: now_ms() + interval * 1000,
        message: "GitHub requested a longer wait. Sign-in will continue automatically.",
      })
    }
    "temporarily_unavailable" | "server_error" => raise DeviceRetry(0)
    "expired_token" | "token_expired" =>
      self.end_device(
        flow, "expired", "The GitHub verification code expired. Start sign-in again.",
      )
    "access_denied" =>
      self.end_device(
        flow, "denied", "GitHub authorization was declined. You can start sign-in again.",
      )
    "incorrect_device_code" | "invalid_grant" =>
      self.end_device(
        flow, "failed", "GitHub no longer accepts this verification code. Start sign-in again.",
      )
    "device_flow_disabled" =>
      self.end_device(
        flow, "failed", "Device Flow must be enabled in the GitHub App settings.",
      )
    "incorrect_client_credentials"
    | "invalid_client"
    | "unsupported_grant_type" =>
      self.end_device(
        flow, "failed", "GitHub rejected the app configuration. Check its client ID and Device Flow settings.",
      )
    _ =>
      self.end_device(
        flow, "failed", "GitHub could not authorize this device. Start sign-in again.",
      )
  }
  true
}

///|
fn App::device_credentials(self : App, flow : DeviceFlow) -> Json raise {
  @json.parse(
    @utf8.decode(
      unseal(
        self.config.key,
        flow.session_id,
        "device:" + flow.id,
        flow.credentials,
      ),
    ),
  )
}

///|
fn App::seal_device(
  self : App,
  flow : DeviceFlow,
  payload : Json,
) -> String raise {
  seal(
    self.config.key,
    flow.session_id,
    "device:" + flow.id,
    @utf8.encode(payload.stringify()),
  )
}

///|
async fn App::device_step(self : App, flow : DeviceFlow) -> Unit {
  if flow.phase == "starting" {
    let payload = device_upstream(
      self.config.oauth_url,
      "/login/device/code",
      "",
      Some({ "client_id": self.config.client_id }),
    )
    guard self.device_current(flow.session_id, flow.id) is Some(_) else {
      return
    }
    if self.device_error(flow, payload) {
      return
    }
    let device_code = string(payload, "device_code")
    let user_code = string(payload, "user_code")
    let uri = string(payload, "verification_uri")
    // oauth_url is either the fixed production GitHub origin or an explicitly
    // enabled loopback test origin. No redirects, query strings or other paths.
    guard uri == self.config.oauth_url + "/login/device" &&
      device_code.length() >= 16 &&
      device_code.length() <= 1024 &&
      user_code.length() == 9 &&
      user_code[4] == '-' &&
      user_code[:4].iter().all(alnum) &&
      user_code[5:].iter().all(alnum) else {
      raise RpcError(
        502, "invalid_github_response", "GitHub returned invalid device verification details.",
      )
    }
    let expires_in = positive_int(payload, "expires_in", 3600).to_int64()
    let interval = if field(payload, "interval") == Json::null() {
      5L
    } else {
      positive_int(payload, "interval", 3600).to_int64()
    }
    self.save_device({
      ..flow,
      phase: "pending",
      user_code,
      verification_uri: uri,
      credentials: self.seal_device(flow, { "device_code": device_code }),
      expires: Int64::min(flow.expires, now() + expires_in),
      interval,
      backoff: 0,
      next_poll: now_ms() + interval * 1000,
      message: "",
    })
    return
  }
  let verifying = if flow.phase == "pending" {
    let credential = self.device_credentials(flow)
    let payload = device_upstream(
      self.config.oauth_url,
      "/login/oauth/access_token",
      "",
      Some({
        "client_id": self.config.client_id,
        "device_code": string(credential, "device_code"),
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
      }),
    )
    guard self.device_current(flow.session_id, flow.id) is Some(_) else {
      return
    }
    if self.device_error(flow, payload) {
      return
    }
    guard !optional_string(payload, "access_token").is_empty() else {
      raise RpcError(
        502, "invalid_github_response", "GitHub did not return an access token.",
      )
    }
    // Persist the redeemed token before /user, which may need retries or a
    // restart. Never redeem a device code twice after a successful exchange.
    let next = {
      ..flow,
      phase: "verifying",
      credentials: self.seal_device(flow, payload),
      token_issued: now(),
      backoff: 0,
      message: "",
    }
    self.save_device(next)
    next
  } else {
    flow
  }
  let tokens = self.device_credentials(verifying)
  let user = device_upstream(
    self.config.api_url,
    "/user",
    string(tokens, "access_token"),
    None,
  )
  guard self.device_current(flow.session_id, flow.id) is Some(_) else { return }
  if self.device_error(verifying, user) {
    return
  }
  let id = github_id(field(user, "id"))
  let login = string(user, "login")
  guard valid_owner(login) else {
    raise RpcError(
      502, "invalid_github_response", "GitHub returned an invalid user.",
    )
  }
  guard self.session(flow.session_id) is Some(session) else { return }
  ignore(
    self.install_tokens(
      session,
      id,
      login,
      tokens,
      issued_at=verifying.token_issued,
      device_id=flow.id,
    ),
  )
}

///|
async fn App::advance_device(
  self : App,
  session_id : String,
  id : String,
) -> Unit {
  let key = session_id + ":" + id
  if self.devices.get(key) is Some(pending) {
    pending.wait()
    return
  }
  guard self.device_current(session_id, id) is Some(flow) &&
    flow.next_poll <= now_ms() else {
    return
  }
  // Reserve before yielding, then set the next deadline after the response too.
  // Millisecond storage avoids rounding down the upstream minimum interval.
  self.save_device({ ..flow, next_poll: now_ms() + flow.interval * 1000, })
  let pending = @async.Lazy(() => {
    @async.protect_from_cancel(() => {
      defer self.devices.remove(key)
      self.device_step(flow) catch {
        error => {
          guard self.device_current(session_id, id) is Some(current) else {
            return
          }
          match error {
            DeviceRetry(seconds) => {
              let backoff = Int64::max(
                current.interval,
                Int64::max(
                  seconds,
                  Int64::min(60, Int64::max(5, current.backoff * 2)),
                ),
              )
              self.save_device({
                ..current,
                backoff,
                next_poll: now_ms() + backoff * 1000,
                message: "GitHub is temporarily unavailable. Sign-in will retry automatically.",
              })
            }
            _ =>
              self.end_device(
                current,
                "failed",
                if error is RpcError(_, _, message) {
                  message
                } else {
                  "The authorization could not be verified. Start sign-in again."
                },
              )
          }
        }
      }
    })
  })
  self.devices[key] = pending
  pending.wait()
}
