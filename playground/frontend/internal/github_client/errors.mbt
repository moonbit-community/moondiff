///|
pub(all) suberror HttpRequestError {
  HttpRequestError(status~ : Int32, code~ : String, detail~ : String)
}

///|
impl Show for HttpRequestError with fn output(self, logger) {
  match self {
    HttpRequestError(status~, code~, detail~) =>
      logger.write_string(
        "Moondiff HTTP request failed (status \{status}, \{code}): \{detail}",
      )
  }
}

///|
pub fn http_error_code(error : Error) -> String? {
  match error {
    RateLimited(_) => Some("rate_limit")
    HttpRequestError(status=_, code~, detail=_) => Some(code)
    _ => None
  }
}

///|
pub(all) suberror GitHubRequestError {
  GitHubRequestError(String)
}

///|
impl Show for GitHubRequestError with fn output(self, logger) {
  match self {
    GitHubRequestError(detail) => logger.write_string(detail)
  }
}

///|
fn rate_limited(error : Error) -> Bool {
  match error {
    RateLimited(_) => true
    HttpRequestError(status=429, ..)
    | HttpRequestError(code="rate_limit", ..) => true
    _ => false
  }
}

///|
pub(all) enum RateLimitReason {
  AnonymousRequests
  AuthenticatedRequests
} derive(Eq)

///|
pub fn RateLimitReason::message(self : RateLimitReason) -> String {
  match self {
    AnonymousRequests =>
      "GitHub is limiting anonymous requests. Sign in to continue."
    AuthenticatedRequests =>
      "GitHub is limiting requests. Please refresh this page later."
  }
}

///|
// Captured at dispatch, so a late anonymous response cannot pause signed-in reads.
pub(all) suberror RateLimited {
  RateLimited(RateLimitReason)
}

///|
impl Show for RateLimited with fn output(self, logger) {
  let RateLimited(reason) = self
  logger.write_string(reason.message())
}

///|
pub fn rate_limit_reason(error : Error) -> RateLimitReason? {
  match error {
    RateLimited(reason) => Some(reason)
    _ => None
  }
}
