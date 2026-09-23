///|
fn github_component(text : String) -> String {
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  for b in @utf8.encode(text) {
    let n = b.to_int()
    let c = n.unsafe_to_char()
    if alnum(c) || c == '-' || c == '_' || c == '.' || c == '~' {
      out.write_char(c)
    } else {
      out.write_string("%")
      out.write_char(hex[n / 16].to_char().unwrap_or('\ufffd'))
      out.write_char(hex[n % 16].to_char().unwrap_or('\ufffd'))
    }
  }
  out.to_string()
}

///|
/// Return the common REST path for browser and server public reads.
pub fn GitHubRequest::public_path(self : GitHubRequest) -> String? {
  match self {
    CommitGet(p) =>
      Some(
        "/repos/\{p.owner}/\{p.repo}/commits/\{p.sha}?per_page=100&page=\{p.page}",
      )
    PullGet(p) => Some("/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}")
    CompareGet(p) =>
      Some("/repos/\{p.owner}/\{p.repo}/compare/\{p.base}...\{p.head}")
    RangeCompareGet(p) =>
      Some(
        "/repos/\{p.owner}/\{p.repo}/compare/\{p.base}...\{p.head}?per_page=100&page=\{p.page}",
      )
    PullCommitPageGet(p) =>
      Some(
        "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/commits?per_page=100&page=\{p.page}",
      )
    ResolveShaGet(p) => Some("/repos/\{p.owner}/\{p.repo}/commits/\{p.sha}")
    PullFiles(p) =>
      Some(
        "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/files?per_page=100&page=\{p.page}",
      )
    ContentGet(p) => {
      let path = p.path
        .split("/")
        .map(part => github_component(part.to_owned()))
        .join("/")
      Some("/repos/\{p.owner}/\{p.repo}/contents/\{path}?ref=\{p.revision}")
    }
    _ => None
  }
}

///|
pub fn CommentsList::public_paths(self : CommentsList) -> Array[String] {
  let base = "/repos/\{self.owner}/\{self.repo}"
  match self.target {
    Pull(number~) =>
      ["\{base}/issues/\{number}/comments", "\{base}/pulls/\{number}/comments"]
    Commit(sha~) | PullCommit(sha~, ..) => ["\{base}/commits/\{sha}/comments"]
  }
}

///|
pub fn normalize_github(value : Json) -> Json {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for key, child in fields {
        if child != Json::null() {
          result[key] = normalize_github(child)
        }
      }
      Json::object(result)
    }
    Array(values) => Json::array(values.map(normalize_github))
    _ => value
  }
}

///|
fn github_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub fn github_id(value : Json) -> String raise {
  match value {
    String(text) if decimal(text) => text
    Number(_, repr=Some(text)) if decimal(text) => text
    Number(number, ..) if number >= 1 &&
      number <= 9007199254740991.0 &&
      number == number.to_int64().to_double() => number.to_int64().to_string()
    _ =>
      raise ProtocolError(
        "invalid_github_response", "GitHub returned an invalid identifier.",
      )
  }
}

///|
pub fn comment_for_protocol(value : Json) -> Json raise {
  guard normalize_github(value) is Object(result) else {
    raise ProtocolError(
      "invalid_github_response", "GitHub returned an invalid comment.",
    )
  }
  result["id"] = Json::string(github_id(github_field(value, "id")))
  if result.get("in_reply_to_id") is Some(id) {
    result["in_reply_to_id"] = Json::string(github_id(id))
  }
  if result.get("side") is Some(side) {
    result["side"] = match side {
      String("LEFT") => ToJson::to_json(CommentSide::Left)
      String("RIGHT") => ToJson::to_json(CommentSide::Right)
      _ =>
        raise ProtocolError(
          "invalid_github_response", "GitHub returned an invalid side.",
        )
    }
  }
  Json::object(result)
}

///|
pub fn[T : FromJson + ToJson] decode_github(value : Json) -> T raise {
  let decoded : T = @json.from_json(value) catch {
    _ =>
      raise ProtocolError(
        "invalid_github_response", "GitHub returned invalid data.",
      )
  }
  guard modeled_fields_equal(ToJson::to_json(decoded), value) else {
    raise ProtocolError(
      "invalid_github_response", "GitHub returned invalid field values.",
    )
  }
  decoded
}

///|
fn modeled_fields_equal(modeled : Json, raw : Json) -> Bool {
  match (modeled, raw) {
    (Object(a), Object(b)) =>
      a
      .iter()
      .all(pair => {
        let (key, value) = pair
        b.get(key).map(raw => modeled_fields_equal(value, raw)).unwrap_or(false)
      })
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i, value in a {
        if !modeled_fields_equal(value, b[i]) {
          return false
        }
      }
      true
    }
    _ => modeled == raw
  }
}
