///|
test "public JSON strips only a leading UTF-8 BOM and SHA responses trim whitespace" {
  assert_eq(
    public_text(b"\xef\xbb\xbf{\"value\":1}", false, false, true, ""),
    "{\"value\":1}",
  )
  assert_eq(public_text(b" \nabc123\r\n", false, true, true, ""), "\"abc123\"")
  assert_eq(
    public_text(b"{\"message\":\"denied\"}", true, false, false, ""),
    "{\"message\":\"denied\"}",
  )
}

///|
test "public source bytes stay lossless and default an empty content type" {
  let raw = b"\xef\xbb\xbf\x00\xff"
  let text = public_text(raw, true, false, true, "")
  let value : @protocol.ApiSource = @json.from_json(@json.parse(text))
  assert_eq(value.size, raw.length())
  assert_eq(@base64.decode(value.base64), raw)
  assert_eq(value.content_type, "application/octet-stream")
}

///|
test "public metadata rejects malformed UTF-8 while source stays byte encoded" {
  try public_text(b"\xff", false, false, true, "") catch {
    @utf8.Malformed(_) => ()
    _ => fail("expected malformed UTF-8")
  } noraise {
    _ => fail("expected failure")
  }
}

///|
test "public rate limit detection distinguishes HTTP status and headers" {
  assert_true(public_rate_limited(429, None, false))
  assert_true(public_rate_limited(403, Some("0"), false))
  assert_true(public_rate_limited(403, None, true))
  assert_false(public_rate_limited(403, Some("1"), false))
  assert_false(public_rate_limited(200, Some("0"), true))
}
