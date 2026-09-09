///|
priv suberror RpcError {
  RpcError(Int, String, String)
}

///|
fn rpc_error(error : Error) -> (Int, Json) {
  let (status, code, message) = match error {
    RpcError(status, code, message) => (status, code, message)
    @protocol.ProtocolError(code, message) => (400, code, message)
    InvalidCiphertext =>
      (
        401, "authentication_required", "Your session cannot be decrypted. Sign in again.",
      )
    @async.TimeoutError =>
      (504, "github_timeout", "GitHub did not respond in time.")
    _ => (500, "internal_error", "The server could not complete the request.")
  }
  (
    status,
    (
      @protocol.Response::Failure(error={ status, code, message, }) :
      @protocol.Response[Unit]).to_json(),
  )
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn string(value : Json, key : String) -> String raise {
  guard field(value, key) is String(text) else {
    raise RpcError(400, "invalid_arguments", "Invalid \{key}.")
  }
  text
}

///|
fn optional_string(value : Json, key : String) -> String {
  match field(value, key) {
    String(text) => text
    _ => ""
  }
}

///|
fn positive_int(value : Json, key : String, maximum : Int) -> Int raise {
  guard field(value, key) is Number(number, ..) &&
    number >= 1 &&
    number <= maximum.to_double() &&
    number == number.to_int().to_double() else {
    raise RpcError(400, "invalid_arguments", "Invalid \{key}.")
  }
  number.to_int()
}

///|
fn decimal(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 20 &&
  value[0] != '0' &&
  value.iter().all(c => c >= '0' && c <= '9')
}

///|
fn alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
using @protocol {
  valid_owner,
  valid_repo,
  valid_sha,
  valid_path,
  valid_attempt_id,
}

///|
fn change_path(path : String) -> Bool {
  let parts = path.split("/").map(StringView::to_owned).collect()
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
    _ => false
  }
}

///|
fn encode_component(text : String) -> String {
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
fn decode_component(text : String) -> String raise {
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
fn normalize(value : Json) -> Json {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for key, child in fields {
        if child != Json::null() {
          result[key] = normalize(child)
        }
      }
      Json::object(result)
    }
    Array(values) => Json::array(values.map(normalize))
    _ => value
  }
}

///|
fn github_id(value : Json) -> String raise {
  match value {
    String(text) if decimal(text) => text
    Number(_, repr=Some(text)) if decimal(text) => text
    Number(number, ..) if number >= 1 &&
      number <= 9007199254740991.0 &&
      number == number.to_int64().to_double() => number.to_int64().to_string()
    _ =>
      raise RpcError(
        502, "invalid_github_response", "GitHub returned an invalid identifier.",
      )
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise {
  guard value is Object(values) else {
    raise RpcError(400, "invalid_arguments", "Expected an object.")
  }
  values
}

///|
fn comment_for_protocol(value : Json) -> Json raise {
  let result = object(normalize(value))
  result["id"] = Json::string(github_id(field(value, "id")))
  if result.get("in_reply_to_id") is Some(id) {
    result["in_reply_to_id"] = Json::string(github_id(id))
  }
  Json::object(result)
}
