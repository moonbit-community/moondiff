///|
async fn static_file(
  app : @storage.App,
  request : @http.Request,
  conn : ResponseWriter,
  raw_path : String,
) -> Unit {
  let path = @common.decode_component(raw_path)
  guard path.has_prefix("/") &&
    (path == "/" || @common.valid_path(path[1:].to_owned())) else {
    raise @common.RpcError(404, "not_found", "Page not found.")
  }
  let name = if path == "/" || @common.change_path(path) {
    "/index.html"
  } else {
    path
  }
  // Canonicalize both paths before opening, including any symlink components.
  let root = app.config.static_dir
  let full = @fs.realpath(root + name) catch {
    _ => raise @common.RpcError(404, "not_found", "Page not found.")
  }
  guard full.has_prefix(root + "/") && @fs.kind(full) == Regular else {
    raise @common.RpcError(404, "not_found", "Page not found.")
  }
  let file = @fs.open(full, mode=ReadOnly)
  defer file.close()
  let content_type = match name {
    [.., .. ".html"] => "text/html; charset=utf-8"
    [.., .. ".css"] => "text/css; charset=utf-8"
    [.., .. ".js"] | [.., .. ".mjs"] => "text/javascript; charset=utf-8"
    [.., .. ".svg"] => "image/svg+xml"
    [.., .. ".png"] => "image/png"
    [.., .. ".wasm"] => "application/wasm"
    _ => "application/octet-stream"
  }
  let fingerprint = static_asset_hash(name)
  // HTML is small and must notice new releases even if size/timestamps match.
  // Keep large assets streaming; their release URLs already contain the hash.
  let body = if name.has_suffix(".html") {
    Some(file.read_all().binary())
  } else {
    None
  }
  let size = match body {
    Some(body) => body.length().to_int64()
    None => file.size()
  }
  let etag = match (fingerprint, body) {
    (Some(hash), _) => "\"\{hash}\""
    (_, Some(body)) => {
      let hash = @xcrypto.bytes_to_hex_string(@xcrypto.sha256(body))
      "\"\{hash}\""
    }
    _ => {
      // Unversioned assets can revalidate without reading/hashing the body.
      let (mtime, mtime_ns) = file.mtime()
      let (ctime, ctime_ns) = file.ctime()
      "W/\"\{size}-\{mtime}-\{mtime_ns}-\{ctime}-\{ctime_ns}\""
    }
  }
  let headers : @http.Headers = {
    "ETag": etag,
    "Cache-Control": if fingerprint is Some(_) {
      "public, max-age=31536000, immutable"
    } else {
      "no-cache"
    },
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https://avatars.githubusercontent.com data:; connect-src 'self' https://api.github.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
  }
  conn.started = true
  if static_not_modified(request.headers.get("If-None-Match"), etag) {
    conn.connection.send_response(304, "Not Modified", extra_headers=headers)
    conn.connection.end_response()
    return
  }
  headers["Content-Type"] = content_type
  headers["Content-Length"] = size.to_string()
  conn.connection.send_response(200, "OK", extra_headers=headers)
  if request.meth != Head {
    match body {
      Some(body) => conn.connection.write(body)
      None => conn.connection.write_reader(file)
    }
  }
  conn.connection.end_response()
}

///|
// Only the exact JS/CSS naming scheme emitted by scripts/static-assets.mjs is
// immutable. Fixed names and arbitrary dotted filenames must revalidate.
fn static_asset_hash(path : String) -> String? {
  let hash = match path {
    [.. "/index.", .. hash, .. ".js"] => hash
    [.. "/styles.", .. hash, .. ".css"] => hash
    _ => return None
  }
  guard hash.length() == 64 &&
    hash.iter().all(c => c is ('0'..='9' | 'a'..='f')) else {
    return None
  }
  Some(hash.to_owned())
}

///|
fn static_not_modified(if_none_match : String?, etag : String) -> Bool {
  guard if_none_match is Some(value) else { return false }
  if value.trim() == "*" {
    return true
  }
  // If-None-Match uses weak comparison, including tags weakened by gzip proxies.
  let current = match etag {
    [.. "W/", .. tag] => tag
    _ => etag[:]
  }
  value
  .split(",")
  .any(tag => {
    let candidate = match tag.trim() {
      [.. "W/", .. tag] => tag
      tag => tag
    }
    candidate == current
  })
}
