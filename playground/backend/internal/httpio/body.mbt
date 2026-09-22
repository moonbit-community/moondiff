///|
/// Read a request or upstream response while enforcing its byte limit.
pub async fn read_bounded(
  reader : &@io.Reader,
  limit : Int,
  source? : Bool = false,
) -> Bytes {
  let out = @buffer.Buffer()
  while reader.read_some(max_len=65536) is Some(bytes) {
    out.write_bytes(bytes)
    guard out.length() <= limit else {
      raise @common.RpcError(
        413,
        if source {
          "source_too_large"
        } else {
          "response_too_large"
        },
        if source {
          "Cannot render: one side is larger than 1 MiB."
        } else {
          "Request or response exceeds the size limit."
        },
      )
    }
  }
  out.to_bytes()
}
