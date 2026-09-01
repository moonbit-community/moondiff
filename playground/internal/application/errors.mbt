///|
fn error_message(error : Error, api : Bool) -> String {
  let detail = error.to_string()
  let lower = detail.to_lower()
  if api {
    match extension_error_code(error) {
      Some("rate_limit") =>
        return "GitHub API rate limit exceeded. Sign in or try again after the reset time."
      Some("authentication_required") =>
        return "Your GitHub session expired. Sign in again."
      Some("not_found_or_not_installed") =>
        return "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
      Some("permission_denied") =>
        return "GitHub denied this request. Install the app for this repository and check its permissions."
      _ => ()
    }
  }
  if api && extension_host_enabled() && lower.contains("rate limit") {
    "GitHub API rate limit exceeded. Sign in or try again after the reset time."
  } else if api && detail.contains("HTTP 401") && extension_host_enabled() {
    "Your GitHub session expired. Sign in again."
  } else if api && detail.contains("HTTP 403") {
    if extension_host_enabled() {
      "GitHub denied this request. Install the app for this repository and check its permissions."
    } else {
      "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later."
    }
  } else if api && detail.contains("HTTP 404") {
    if extension_host_enabled() {
      "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
    } else {
      "GitHub could not find that public repository, commit, or pull request."
    }
  } else {
    detail
  }
}

///|
fn comment_failure_message(error : Error) -> String {
  match extension_error_code(error) {
    Some("authentication_required") =>
      return "Your GitHub session expired. Sign in again, then retry."
    Some("not_found_or_not_installed") =>
      return "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
    Some("permission_denied") =>
      return "GitHub denied this action. Install the app for this repository and check its Pull requests permission."
    Some("invalid_comment_anchor") =>
      return "GitHub rejected this comment anchor. Refresh the diff and choose the line again."
    _ => ()
  }
  let detail = error_message(error, true)
  if detail.contains("HTTP 401") {
    "Your GitHub session expired. Sign in again, then retry."
  } else if detail.contains("HTTP 403") {
    "GitHub denied this action. Install the app for this repository and check its Pull requests permission."
  } else if detail.contains("HTTP 404") {
    "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
  } else if detail.contains("HTTP 422") {
    "GitHub rejected this comment anchor. Refresh the diff and choose the line again."
  } else {
    detail
  }
}
