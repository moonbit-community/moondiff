///|
priv suberror DeviceRetry {
  DeviceRetry(Int64)
}

///|
fn retry_seconds(response : @http.Response) -> Int64 {
  let value = response.headers.get("Retry-After").unwrap_or("")
  if @common.decimal(value) && value.length() <= 8 {
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
  let (response, bytes) = @github.upstream(
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
    @common.RpcError(_, _, _) as error => raise error
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
  let payload = @github.upstream_json(bytes)
  if !@common.optional_string(payload, "error").is_empty() {
    return payload
  }
  guard response.code == 200 else {
    raise @common.RpcError(
      502, "device_authorization_failed", "GitHub rejected device authorization. Check the GitHub @storage.App configuration and try again.",
    )
  }
  payload
}

///|
fn device_error(
  app : @storage.App,
  flow : @storage.DeviceFlow,
  payload : Json,
) -> Bool raise {
  let error = @common.optional_string(payload, "error")
  if error.is_empty() {
    return false
  }
  match error {
    "authorization_pending" if flow.phase == "pending" =>
      app.save_device({
        ..flow,
        backoff: 0,
        message: "",
        next_poll: @storage.now_ms() + flow.interval * 1000,
      })
    "slow_down" if flow.phase == "pending" => {
      let returned = if @common.field(payload, "interval") is Number(n, ..) &&
        n >= 1 &&
        n <= 86400 {
        n.to_int64()
      } else {
        0L
      }
      let interval = Int64::max(flow.interval + 5, returned)
      app.save_device({
        ..flow,
        interval,
        backoff: 0,
        next_poll: @storage.now_ms() + interval * 1000,
        message: "GitHub requested a longer wait. Sign-in will continue automatically.",
      })
    }
    "temporarily_unavailable" | "server_error" => raise DeviceRetry(0)
    "expired_token" | "token_expired" =>
      app.end_device(
        flow, "expired", "The GitHub verification code expired. Start sign-in again.",
      )
    "access_denied" =>
      app.end_device(
        flow, "denied", "GitHub authorization was declined. You can start sign-in again.",
      )
    "incorrect_device_code" | "invalid_grant" =>
      app.end_device(
        flow, "failed", "GitHub no longer accepts this verification code. Start sign-in again.",
      )
    "device_flow_disabled" =>
      app.end_device(
        flow, "failed", "Device Flow must be enabled in the GitHub @storage.App settings.",
      )
    "incorrect_client_credentials"
    | "invalid_client"
    | "unsupported_grant_type" =>
      app.end_device(
        flow, "failed", "GitHub rejected the app configuration. Check its client ID and Device Flow settings.",
      )
    _ =>
      app.end_device(
        flow, "failed", "GitHub could not authorize this device. Start sign-in again.",
      )
  }
  true
}

///|
fn device_credentials(
  app : @storage.App,
  flow : @storage.DeviceFlow,
) -> Json raise {
  @json.parse(
    @utf8.decode(
      @crypto.unseal(
        app.config.key,
        flow.session_id,
        "device:" + flow.id,
        flow.credentials,
      ),
    ),
  )
}

///|
fn seal_device(
  app : @storage.App,
  flow : @storage.DeviceFlow,
  payload : Json,
) -> String raise {
  @crypto.seal(
    app.config.key,
    flow.session_id,
    "device:" + flow.id,
    @utf8.encode(payload.stringify()),
  )
}

///|
async fn device_step(app : @storage.App, flow : @storage.DeviceFlow) -> Unit {
  if flow.phase == "starting" {
    let payload = device_upstream(
      app.config.oauth_url,
      "/login/device/code",
      "",
      Some({ "client_id": app.config.client_id }),
    )
    guard app.device_current(flow.session_id, flow.id) is Some(_) else {
      return
    }
    if device_error(app, flow, payload) {
      return
    }
    let device_code = @common.string(payload, "device_code")
    let user_code = @common.string(payload, "user_code")
    let uri = @common.string(payload, "verification_uri")
    // oauth_url is either the fixed production GitHub origin or an explicitly
    // enabled loopback test origin. No redirects, query strings or other paths.
    guard uri == app.config.oauth_url + "/login/device" &&
      device_code.length() >= 16 &&
      device_code.length() <= 1024 &&
      user_code.length() == 9 &&
      user_code[4] == '-' &&
      user_code[:4].iter().all(@common.alnum) &&
      user_code[5:].iter().all(@common.alnum) else {
      raise @common.RpcError(
        502, "invalid_github_response", "GitHub returned invalid device verification details.",
      )
    }
    let expires_in = @common.positive_int(payload, "expires_in", 3600).to_int64()
    let interval = if @common.field(payload, "interval") == Json::null() {
      5L
    } else {
      @common.positive_int(payload, "interval", 3600).to_int64()
    }
    app.save_device({
      ..flow,
      phase: "pending",
      user_code,
      verification_uri: uri,
      credentials: seal_device(app, flow, { "device_code": device_code }),
      expires: Int64::min(flow.expires, @storage.now() + expires_in),
      interval,
      backoff: 0,
      next_poll: @storage.now_ms() + interval * 1000,
      message: "",
    })
    return
  }
  let verifying = if flow.phase == "pending" {
    let credential = device_credentials(app, flow)
    let payload = device_upstream(
      app.config.oauth_url,
      "/login/oauth/access_token",
      "",
      Some({
        "client_id": app.config.client_id,
        "device_code": @common.string(credential, "device_code"),
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
      }),
    )
    guard app.device_current(flow.session_id, flow.id) is Some(_) else {
      return
    }
    if device_error(app, flow, payload) {
      return
    }
    guard !@common.optional_string(payload, "access_token").is_empty() else {
      raise @common.RpcError(
        502, "invalid_github_response", "GitHub did not return an access token.",
      )
    }
    // Persist the redeemed token before /user, which may need retries or a
    // restart. Never redeem a device code twice after a successful exchange.
    let next = {
      ..flow,
      phase: "verifying",
      credentials: seal_device(app, flow, payload),
      token_issued: @storage.now(),
      backoff: 0,
      message: "",
    }
    app.save_device(next)
    next
  } else {
    flow
  }
  let tokens = device_credentials(app, verifying)
  let user = device_upstream(
    app.config.api_url,
    "/user",
    @common.string(tokens, "access_token"),
    None,
  )
  guard app.device_current(flow.session_id, flow.id) is Some(_) else { return }
  if device_error(app, verifying, user) {
    return
  }
  let id = @common.github_id(@common.field(user, "id"))
  let login = @common.string(user, "login")
  guard @common.valid_owner(login) else {
    raise @common.RpcError(
      502, "invalid_github_response", "GitHub returned an invalid user.",
    )
  }
  guard app.session(flow.session_id) is Some(session) else { return }
  ignore(
    app.install_tokens(
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
pub async fn advance_device(
  app : @storage.App,
  session_id : String,
  id : String,
) -> Unit {
  let key = session_id + ":" + id
  if app.devices.get(key) is Some(pending) {
    pending.wait()
    return
  }
  guard app.device_current(session_id, id) is Some(flow) &&
    flow.next_poll <= @storage.now_ms() else {
    return
  }
  // Reserve before yielding, then set the next deadline after the response too.
  // Millisecond storage avoids rounding down the upstream minimum interval.
  app.save_device({
    ..flow,
    next_poll: @storage.now_ms() + flow.interval * 1000,
  })
  let pending = @async.Lazy(() => {
    @async.protect_from_cancel(() => {
      defer app.devices.remove(key)
      device_step(app, flow) catch {
        error => {
          guard app.device_current(session_id, id) is Some(current) else {
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
              app.save_device({
                ..current,
                backoff,
                next_poll: @storage.now_ms() + backoff * 1000,
                message: "GitHub is temporarily unavailable. Sign-in will retry automatically.",
              })
            }
            _ =>
              app.end_device(
                current,
                "failed",
                if error is @common.RpcError(_, _, message) {
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
  app.devices[key] = pending
  pending.wait()
}
