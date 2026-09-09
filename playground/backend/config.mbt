///|
priv struct Config {
  listen : String
  public_url : String
  static_dir : String
  database : String
  key : Bytes
  client_id : String
  install_url : String
  api_url : String
  oauth_url : String
  secure : Bool
}

///|
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
fn required_setting(name : String) -> String raise {
  let value = setting(name, "")
  guard !value.is_empty() &&
    !value.iter().any(c => c.to_int() < 32 || c.to_int() == 127) else {
    fail("Missing or invalid \{name}")
  }
  value
}

///|
fn root_url(value : String, local_only? : Bool = false) -> String raise {
  let origin = value.trim_end(chars="/").to_owned()
  let parts = origin.split("://").map(StringView::to_owned).collect()
  guard parts is [scheme, raw_authority] &&
    (scheme == "https" || scheme == "http") &&
    !raw_authority.is_empty() else {
    fail("Expected an absolute root URL")
  }
  let authority = raw_authority.to_lower()
  guard authority
    .iter()
    .all(c => {
      alnum(c) || c == '.' || c == '-' || c == ':' || c == '[' || c == ']'
    }) else {
    fail("Invalid URL authority")
  }
  let loopback = ["localhost", "127.0.0.1", "[::1]"]
    .iter()
    .any(host => authority == host || authority.has_prefix(host + ":"))
  guard (scheme == "https" || loopback) && (!local_only || loopback) else {
    fail("HTTP is only allowed on loopback; production requires HTTPS")
  }
  let host_end = if authority.has_prefix("[") {
    guard authority.has_prefix("[::1]") else { fail("Invalid IPv6 host") }
    5
  } else {
    authority.find(":").unwrap_or(authority.length())
  }
  guard host_end > 0 else { fail("Missing URL host") }
  let host = authority[:host_end].to_owned()
  guard host == "[::1]" ||
    host
    .split(".")
    .all(label => {
      !label.is_empty() &&
      label.iter().all(c => alnum(c) || c == '-') &&
      !label.has_prefix("-") &&
      !label.has_suffix("-")
    }) else {
    fail("Invalid URL host")
  }
  if host_end < authority.length() {
    guard authority[host_end] == ':' else { fail("Invalid URL port") }
    let port = authority[host_end + 1:].to_owned()
    guard decimal(port) && port.length() <= 5 else { fail("Invalid URL port") }
    let number : Int = @json.from_json(@json.parse(port))
    guard number <= 65535 else { fail("Invalid URL port") }
    if (scheme == "https" && number == 443) ||
      (scheme == "http" && number == 80) {
      return "\{scheme}://\{host}"
    }
  }
  "\{scheme}://\{authority}"
}

///|
fn Config::load() -> Config raise {
  let public_url = root_url(
    setting("MOONDIFF_PUBLIC_URL", "http://localhost:4173"),
  )
  let key = @base64.decode(required_setting("MOONDIFF_TOKEN_KEY"))
  guard key.length() == 64 else {
    fail("MOONDIFF_TOKEN_KEY must encode exactly 64 random bytes")
  }
  let install_url = required_setting("MOONDIFF_GITHUB_INSTALL_URL")
  guard install_url.has_prefix("https://github.com/apps/") &&
    !install_url.contains("\"") &&
    !install_url.contains("<") else {
    fail("Invalid GitHub installation URL")
  }
  let test_mode = setting("MOONDIFF_TEST_MODE", "") == "1"
  let api_url = if test_mode {
    root_url(required_setting("MOONDIFF_TEST_GITHUB_URL"), local_only=true)
  } else {
    "https://api.github.com"
  }
  let oauth_url = if test_mode {
    root_url(required_setting("MOONDIFF_TEST_OAUTH_URL"), local_only=true)
  } else {
    "https://github.com"
  }
  if test_mode {
    ignore(root_url(public_url, local_only=true))
  }
  {
    listen: setting("MOONDIFF_LISTEN", "127.0.0.1:4173"),
    public_url,
    static_dir: setting("MOONDIFF_STATIC_DIR", "dist/static"),
    database: setting("MOONDIFF_DATABASE", "moondiff.sqlite3"),
    key,
    client_id: required_setting("MOONDIFF_GITHUB_CLIENT_ID"),
    install_url,
    api_url,
    oauth_url,
    secure: public_url.has_prefix("https://"),
  }
}
