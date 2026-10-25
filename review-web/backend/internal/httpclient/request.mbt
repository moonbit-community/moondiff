///|
/// Framing/encoding failures retain the existing transport error handling in
/// RPC, device authorization and partial CI reads, and are never replayed.
pub suberror ResponseProtocolError

///|
fn disconnected(error : Error) -> Bool {
  match error {
    @io.ReaderClosed | @tls.ConnectionClosed => true
    @os_error.OSError(errno, ..) =>
      // The dependency exposes no portable predicate for these errors.
      match @async.platform {
        Linux => errno is (32 | 103 | 104 | 107)
        MacOS => errno is (32 | 53 | 54 | 57)
        Windows => errno is (109 | 232 | 10053 | 10054 | 10057)
      }
    _ => false
  }
}

///|
fn reusable_response(
  response : @http.Response,
  meth : @http.RequestMethod,
) -> Bool {
  if response.headers
    .get("Connection")
    .unwrap_or("")
    .split(",")
    .any(value => value.trim().to_owned().to_lower() == "close") ||
    response.code == 101 {
    return false
  }
  meth == Head ||
  response.code == 204 ||
  response.code == 304 ||
  response.headers.contains("Content-Length") ||
  response.headers.get("Transfer-Encoding").unwrap_or("").to_lower() ==
  "chunked"
}

///|
/// Queueing, connection setup, the one permitted recovery and body consumption
/// all share the caller's original 30-second deadline.
pub async fn Pool::request(
  self : Pool,
  path : String,
  meth : @http.RequestMethod,
  headers : @http.Headers,
  body : Bytes?,
  limit : Int32,
  source~ : Bool = false,
) -> (@http.Response, Bytes) {
  // Decode explicitly: Client's automatic gzip decoding removes Content-Length
  // before exposing headers, losing the information needed for safe reuse.
  headers["Accept-Encoding"] = "gzip,identity"
  @async.with_timeout(30000, () => {
    self.permits.acquire()
    defer self.permits.release()
    for attempt in 0..<=1 {
      let (connection, reused) = self.borrow(fresh=attempt == 1)
      let mut reusable = false
      defer self.give_back(connection, reusable)
      let response = try {
        connection.client.request(meth, path, extra_headers=headers)
        if body is Some(bytes) {
          connection.client.write(bytes)
        }
        connection.client.end_request()
      } catch {
        error if attempt == 0 &&
          reused &&
          (meth == Get || meth == Head) &&
          !@async.is_being_cancelled() &&
          disconnected(error) => continue
        error => raise error
      }
      let persistent = reusable_response(response, meth)
      let encoding = response.headers
        .get("Content-Encoding")
        .unwrap_or("")
        .to_lower()
      let bytes = if meth == Head ||
        response.code == 204 ||
        response.code == 304 ||
        encoding.is_empty() {
        @httpio.read_bounded(connection.client, limit, source~)
      } else if encoding == "gzip" {
        let bytes = @httpio.read_bounded(
          @gzip.Decoder(connection.client),
          limit,
          source~,
        )
        // Finish the HTTP framing too (including chunk trailers). A gzip footer
        // alone does not mean the underlying HTTP response has been consumed.
        guard connection.client.read_some() is None else {
          raise ResponseProtocolError
        }
        response.headers.remove("Content-Length")
        bytes
      } else {
        raise ResponseProtocolError
      }
      reusable = persistent
      return (response, bytes)
    }
    abort("HTTP recovery exhausted")
  })
}
