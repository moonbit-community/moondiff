///|
/// Read a request or upstream response while enforcing its byte limit.
pub async fn read_bounded(
  reader : &@io.BinaryReader,
  limit : Int32,
  source~ : Bool = false,
) -> Bytes {
  let out = @buffer.Buffer()
  let chunk : FixedArray[Byte] = FixedArray::make(65536, b'\x00')
  for ;; {
    let length = reader.read_into(chunk.mut_view())
    if length == 0 {
      break
    }
    guard length <= limit - out.length() else {
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
    out.write_bytesview(Bytes::from_array(chunk[:length]))
  }
  out.to_bytes()
}
