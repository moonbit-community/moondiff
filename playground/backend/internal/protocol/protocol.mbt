///|
pub(all) suberror RpcError {
  RpcError(Int, String, String)
}

///|
pub fn rpc_error(error : Error) -> (Int, Json) {
  let (status, code, message) = match error {
    RpcError(status, code, message) => (status, code, message)
    @api.ProtocolError(code, message) => (400, code, message)
    @async.TimeoutError =>
      (504, "github_timeout", "GitHub did not respond in time.")
    _ => (500, "internal_error", "The server could not complete the request.")
  }
  (
    status,
    ToJson::to_json(
      (Failure(error={ status, code, message, }) : @api.Response[Unit]),
    ),
  )
}

///|
pub fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub fn string(value : Json, key : String) -> String raise {
  guard field(value, key) is String(text) else {
    raise RpcError(400, "invalid_arguments", "Invalid \{key}.")
  }
  text
}

///|
pub fn optional_string(value : Json, key : String) -> String {
  match field(value, key) {
    String(text) => text
    _ => ""
  }
}

///|
pub fn positive_int(value : Json, key : String, maximum : Int) -> Int raise {
  guard field(value, key) is Number(number, ..) &&
    number >= 1 &&
    number <= maximum.to_double() &&
    number == number.to_int().to_double() else {
    raise RpcError(400, "invalid_arguments", "Invalid \{key}.")
  }
  number.to_int()
}

///|
pub fn decimal(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 20 &&
  value[0] != '0' &&
  value.iter().all(c => c >= '0' && c <= '9')
}

///|
pub fn alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
pub using @api {
  valid_owner,
  valid_repo,
  valid_sha,
  valid_path,
  valid_attempt_id,
}

///|
pub fn change_path(path : String) -> Bool {
  let parts = path.split("/").map(StringView::to_owned).collect()
  fn interval(value : String) -> Bool {
    match value.split_once("..") {
      Some((base, head)) =>
        valid_sha(base.to_owned()) && valid_sha(head.to_owned())
      None => false
    }
  }
  match parts {
    ["", owner, repo, "commit", sha] =>
      valid_owner(owner) && valid_repo(repo) && valid_sha(sha)
    ["", owner, repo, "pull", number] =>
      valid_owner(owner) && valid_repo(repo) && decimal(number)
    ["", owner, repo, "pull", number, "commits", sha] =>
      valid_owner(owner) &&
      valid_repo(repo) &&
      decimal(number) &&
      valid_sha(sha)
    ["", owner, repo, "compare", value] =>
      valid_owner(owner) && valid_repo(repo) && interval(value)
    ["", owner, repo, "pull", number, "compare", value] =>
      valid_owner(owner) &&
      valid_repo(repo) &&
      decimal(number) &&
      interval(value)
    _ => false
  }
}

///|
pub fn encode_component(text : String) -> String {
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
pub fn decode_component(text : String) -> String raise {
  let input = @utf8.encode(text)
  let out = @buffer.Buffer()
  let mut i = 0
  while i < input.length() {
    if input[i] == b'%' {
      guard i + 2 < input.length() else {
        raise RpcError(400, "invalid_path", "Invalid URL encoding.")
      }
      let mut number = 0
      for j in (i + 1)..<(i + 3) {
        let c = input[j].to_int()
        let digit = if c >= 48 && c <= 57 {
          c - 48
        } else if c >= 65 && c <= 70 {
          c - 55
        } else if c >= 97 && c <= 102 {
          c - 87
        } else {
          -1
        }
        guard digit >= 0 else {
          raise RpcError(400, "invalid_path", "Invalid URL encoding.")
        }
        number = number * 16 + digit
      }
      out.write_byte(number.to_byte())
      i += 3
    } else {
      out.write_byte(input[i])
      i += 1
    }
  }
  @utf8.decode(out.to_bytes())
}

///|
pub fn normalize(value : Json) -> Json {
  @api.normalize_github(value)
}

///|
pub fn github_id(value : Json) -> String raise {
  @api.github_id(value) catch {
    @api.ProtocolError(_, message) =>
      raise RpcError(502, "invalid_github_response", message)
    error => raise error
  }
}

///|
pub fn comment_for_protocol(value : Json) -> Json raise {
  @api.comment_for_protocol(value) catch {
    @api.ProtocolError(_, message) =>
      raise RpcError(502, "invalid_github_response", message)
    error => raise error
  }
}

///|
pub fn[T : FromJson + ToJson] decode_github(value : Json) -> T raise {
  @api.decode_github(value) catch {
    @api.ProtocolError(_, message) =>
      raise RpcError(502, "invalid_github_response", message)
    error => raise error
  }
}

///|
pub fn resolved_sha(requested : String, response : String) -> String raise {
  @api.resolved_sha(requested, response) catch {
    @api.ProtocolError(_, message) =>
      raise RpcError(502, "invalid_github_response", message)
    error => raise error
  }
}
