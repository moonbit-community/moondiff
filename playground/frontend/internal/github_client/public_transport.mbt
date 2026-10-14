///|
priv struct PublicRead {
  controller : @browser.AbortController
  source : Bool
  sha : Bool
  completed : (Int32, String, Bool) -> Unit
  failed : (String, String) -> Unit
  buffer : @buffer.Buffer
  mut timed_out : Bool
  mut finished : Bool
  mut timer : Int32
}

///|
fn PublicRead::finish(self : PublicRead) -> Unit {
  self.finished = true
  @dom.window().clear_timeout(self.timer)
}

///|
fn PublicRead::network_error(self : PublicRead, detail : String) -> Unit {
  if self.finished {
    return
  }
  self.finish()
  if self.timed_out {
    (self.failed)(
      "network_error", "GitHub did not respond within 30 seconds. Try again.",
    )
  } else if !self.controller.aborted() {
    (self.failed)(
      "network_error",
      "Could not reach GitHub from this browser (network or CORS policy): " +
      detail,
    )
  }
}

///|
fn public_text(
  bytes : Bytes,
  source : Bool,
  sha : Bool,
  ok : Bool,
  content_type : String,
) -> String raise {
  if sha && ok {
    Json(@utf8.decode(bytes, ignore_bom=true).trim().to_owned()).stringify()
  } else if source && ok {
    Json::object({
      "base64": Json(@base64.encode(bytes)),
      "size": Json(bytes.length()),
      "content_type": Json(
        if content_type.is_empty() {
          "application/octet-stream"
        } else {
          content_type
        },
      ),
    }).stringify()
  } else {
    @utf8.decode(bytes, ignore_bom=true)
  }
}

///|
fn public_rate_limited(
  status : Int32,
  remaining : String?,
  retry_after : Bool,
) -> Bool {
  status == 429 || (status == 403 && (remaining == Some("0") || retry_after))
}

///|
fn PublicRead::read(
  self : PublicRead,
  response : @browser.Response,
  reader : @browser.Reader,
) -> Unit {
  @browser.subscribe(
    reader.read(),
    chunk => {
      if self.finished {
        return
      }
      let done : Bool = chunk.get_with_string("done")
      if done {
        try {
          let text = public_text(
            self.buffer.to_bytes(),
            self.source,
            self.sha,
            response.ok(),
            response.header("Content-Type").to_option().unwrap_or(""),
          )
          let rate_limited = public_rate_limited(
            response.status(),
            response.header("X-RateLimit-Remaining").to_option(),
            response.has_header("Retry-After"),
          )
          (self.completed)(response.status(), text, rate_limited)
          self.finish()
        } catch {
          @utf8.Malformed(_) =>
            self.network_error(
              "The encoded data was not valid for encoding utf-8.",
            )
          error => self.network_error(error.to_string())
        }
      } else {
        let bytes = @browser.chunk_bytes(chunk)
        let limit = if self.source { 1048576 } else { 8388608 }
        if self.buffer.length() + bytes.length() > limit {
          @browser.subscribe(
            reader.cancel(),
            _ => {
              if !self.finished {
                (self.failed)(
                  if self.source {
                    "source_too_large"
                  } else {
                    "response_too_large"
                  },
                  if self.source {
                    "Cannot render: one side is larger than 1 MiB."
                  } else {
                    "GitHub response exceeds 8 MiB."
                  },
                )
                self.finish()
              }
            },
            error => self.network_error(@browser.error_message(error)),
          )
        } else {
          self.buffer.write_bytes(bytes)
          self.read(response, reader)
        }
      }
    },
    error => self.network_error(@browser.error_message(error)),
  )
}

///|
fn fetch_public_text(
  path : String,
  source : Bool,
  sha : Bool,
  completed : (Int32, String, Bool) -> Unit,
  failed : (String, String) -> Unit,
) -> () -> Unit {
  let state : PublicRead = {
    controller: @browser.AbortController::new(),
    source,
    sha,
    completed,
    failed,
    buffer: @buffer.Buffer(),
    timed_out: false,
    finished: false,
    timer: 0,
  }
  state.timer = @dom.window().set_timeout(
    () => {
      state.timed_out = true
      state.controller.abort()
    },
    30000,
  )
  let options = @js.Object::new()
  options.set("method", "GET")
  options.set("mode", "cors")
  options.set("credentials", "omit")
  options.set("cache", "no-store")
  options.set("redirect", "error")
  options.set("signal", state.controller.signal())
  let headers = @js.Object::new()
  headers.set(
    "Accept",
    if sha {
      "application/vnd.github.sha"
    } else if source {
      "application/vnd.github.raw+json"
    } else {
      "application/vnd.github+json"
    },
  )
  options.set("headers", headers.to_value())
  @browser.subscribe(
    @browser.fetch("https://api.github.com" + path, options.to_value()),
    response => state.read(response, response.reader()),
    error => state.network_error(@browser.error_message(error)),
  )
  () => {
    state.controller.abort()
    state.finish()
  }
}

///|
fn github_response(
  status : Int32,
  text : String,
  rate_limited : Bool,
) -> Json raise {
  if status < 200 || status >= 300 {
    let payload = @json.parse(text) catch { _ => Json::null() }
    let message = match payload {
      Object(fields) =>
        match fields.get("message") {
          Some(String(message)) => message
          _ => "GitHub request failed."
        }
      _ => "GitHub request failed."
    }
    let rate_limited = rate_limited ||
      (status == 403 && message.to_lower().contains("rate limit"))
    let (code, detail) = if rate_limited {
      (
        "rate_limit", "GitHub's public API rate limit was reached. Sign in or try again later.",
      )
    } else if status == 404 {
      (
        "not_found_or_not_installed", "GitHub could not find this public resource. Sign in for private repositories.",
      )
    } else if status == 403 {
      ("permission_denied", message)
    } else {
      ("github_http_\{status}", message)
    }
    raise HttpRequestError(status~, code~, detail~)
  }
  @json.parse(text) catch {
    _ =>
      raise HttpRequestError(
        status=502,
        code="invalid_github_response",
        detail="GitHub returned invalid JSON.",
      )
  }
}

///|
fn public_fetch(
  path : String,
  source : Bool,
  done : (Result[Json, Error]) -> Unit,
  sha~ : Bool = false,
) -> () -> Unit {
  fetch_public_text(
    path,
    source,
    sha,
    (status, text, rate_limited) => {
      done(
        Ok(github_response(status, text, rate_limited)) catch {
          error => Err(error)
        },
      )
    },
    (code, detail) => done(Err(HttpRequestError(status=0, code~, detail~))),
  )
}
