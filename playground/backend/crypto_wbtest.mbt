///|
test "encryption padding boundaries and fresh IVs" {
  let key = random_bytes(64)
  for length in [0, 1, 15, 16, 17, 31, 32, 64, 4096] {
    let plaintext = random_bytes(length)
    let encrypted = seal(key, "session", "123", plaintext)
    assert_eq(unseal(key, "session", "123", encrypted), plaintext)
    assert_true(encrypted != seal(key, "session", "123", plaintext))
  }
}

///|
test "ciphertext version IV MAC key and identity tampering fail closed" {
  let key = random_bytes(64)
  let encrypted = seal(key, "session", "123", b"ghu_secret")
  for
    (sid, uid, test_key) in [
      ("other", "123", key),
      ("session", "456", key),
      ("session", "123", random_bytes(64)),
    ] {
    try unseal(test_key, sid, uid, encrypted) catch {
      InvalidCiphertext => ()
      error => raise error
    } noraise {
      _ => fail("accepted tampering")
    }
  }
  let data = @base64.decode(encrypted)
  for index in 0..<data.length() {
    let changed = data.to_array()
    changed[index] = (changed[index].to_int() ^ 1).to_byte()
    try
      unseal(key, "session", "123", @base64.encode(Bytes::from_array(changed)))
    catch {
      InvalidCiphertext => ()
      error => raise error
    } noraise {
      _ => fail("accepted byte tampering")
    }
  }
  for
    invalid in [
      b"", b"123456789012345\x00", b"123456789012345\x11", b"12345678901234\x01\x02",
    ] {
    try unpad(invalid) catch {
      InvalidCiphertext => ()
      error => raise error
    } noraise {
      _ => fail("accepted invalid padding")
    }
  }
}

///|
test "sensitive byte equality handles empty values lengths and repeated differences" {
  for value in [b"", b"abc", b"\x00\x80\xff"] {
    assert_true(constant_time_equal(value, Bytes::from_array(value.to_array())))
  }
  for
    (left, right) in [
      (b"", b"\x00"),
      (b"abc", b"ab"),
      (b"abc", b"abc\x00"),
      (b"\x00\x00", b"\x01\x01"),
      (b"\x00\xff", b"\xff\x00"),
    ] {
    assert_false(constant_time_equal(left, right))
    assert_false(constant_time_equal(right, left))
  }
}

///|
test "sensitive byte equality rejects every bit at every MAC and token position" {
  // HMAC bytes, Base64url CSRF tokens and hex-encoded state hashes, plus
  // adjacent lengths that exercise remainder handling in optimized loops.
  for length in [1, 15, 16, 17, 31, 32, 33, 43, 63, 64, 65] {
    let original = Bytes::from_array(
      Array::makei(length, i => (i * 37 + 128).to_byte()),
    )
    assert_true(
      constant_time_equal(original, Bytes::from_array(original.to_array())),
    )
    for index in 0..<length {
      for bit in 0..<8 {
        let changed = original.to_array()
        changed[index] = (changed[index].to_int() ^ (1 << bit)).to_byte()
        assert_false(constant_time_equal(original, Bytes::from_array(changed)))
      }
    }
  }
}

///|
test "Session ID and CSRF encoding replaces every Base64 special character" {
  assert_eq(base64url(b"\xfb\xef\xbe\xfb\xef\xbe"), "--------")
  assert_eq(base64url(b"\xff\xff\xff\xff\xff\xff"), "________")
  for _ in 0..<100 {
    let value = random_id()
    assert_eq(value.length(), 43)
    assert_true(value.iter().all(c => alnum(c) || c == '-' || c == '_'))
  }
}
