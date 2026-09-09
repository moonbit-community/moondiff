///|
pub(all) suberror ExtensionRequestError {
  ExtensionRequestError(status~ : Int, code~ : String, detail~ : String)
}

///|
impl Show for ExtensionRequestError with fn output(self, logger) {
  match self {
    ExtensionRequestError(status~, code~, detail~) =>
      logger.write_string(
        "Moondiff extension request failed (status \{status}, \{code}): \{detail}",
      )
  }
}

///|
pub fn extension_error_code(error : Error) -> String? {
  match error {
    ExtensionRequestError(status=_, code~, detail=_) => Some(code)
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
