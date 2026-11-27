///|
async test "bounded binary reads preserve exact limits across chunk boundaries" {
  for length in [0, 1, 65535, 65536, 65537, 131073] {
    let expected = Bytes::makei(length, i => (i % 251).to_byte())
    let reader = @io.MemoryReader(writer => writer.write(expected))
    defer reader.close()
    assert_eq(read_bounded(reader, length), expected)
  }
}

///|
async test "bounded binary reads accumulate short reads until EOF" {
  let reader = @io.MemoryReader(writer => {
    writer.write(b"ab")
    @async.pause()
    writer.write(b"\x00\xff")
    @async.pause()
    writer.write(b"c")
  })
  defer reader.close()
  assert_eq(read_bounded(reader, 5), b"ab\x00\xffc")
}

///|
async test "bounded binary reads reject one excess byte with the source-specific error" {
  for limit in [0, 65536, 131072] {
    for source in [false, true] {
      let reader = @io.MemoryReader(writer => {
        writer.write(Bytes::make(limit + 1, b'x'))
      })
      defer reader.close()
      try read_bounded(reader, limit, source~) catch {
        @common.RpcError(status, code, _) => {
          assert_eq(status, 413)
          assert_eq(
            code,
            if source {
              "source_too_large"
            } else {
              "response_too_large"
            },
          )
        }
        error => raise error
      } noraise {
        _ => fail("accepted a body beyond its byte limit")
      }
    }
  }
}

///|
priv suberror BodyReadFailure

///|
async test "bounded binary reads propagate failures after partial data" {
  let reader = @io.MemoryReader(writer => {
    writer.write(b"partial")
    @async.pause()
    raise BodyReadFailure
  })
  defer reader.close()
  try read_bounded(reader, 1024) catch {
    @io.ReaderError::TransportError(BodyReadFailure, ..) => ()
    error => raise error
  } noraise {
    _ => fail("returned a partial body after a reader failure")
  }
}
