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
    HttpRequestError(status=429, ..)
    | HttpRequestError(code="rate_limit", ..) => true
    _ => false
  }
}
