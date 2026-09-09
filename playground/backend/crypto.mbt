///|
priv suberror InvalidCiphertext

///|
fn random_bytes(length : Int) -> Bytes raise {
  guard @env.rand(length) is Some(bytes) else {
    fail("System entropy unavailable")
  }
  bytes
}

///|
fn random_id() -> String raise {
  base64url(random_bytes(32))
}

///|
fn base64url(bytes : Bytes) -> String {
  @base64.encode(bytes, padding=false)
  .replace_all(old="+", new="-")
  .replace_all(old="/", new="_")
}

///|
fn digest(text : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
// Lengths are public. For equal lengths, consume every byte without a
// content-dependent branch or early return. Keep this routine separate for
// generated-code review; recheck optimized output when changing toolchains.
#inline(never)
fn constant_time_equal(left : Bytes, right : Bytes) -> Bool {
  guard left.length() == right.length() else { return false }
  for i = 0, difference = 0; i < left.length(); {
    continue i + 1, difference | (left[i].to_int() ^ right[i].to_int())
  } nobreak {
    difference == 0
  }
}

///|
fn pad(data : Bytes) -> Bytes {
  let padding = 16 - data.length() % 16
  let out = @buffer.from_bytes(data)
  for _ in 0..<padding {
    out.write_byte(padding.to_byte())
  }
  out.to_bytes()
}

///|
fn unpad(data : Bytes) -> Bytes raise {
  guard !data.is_empty() && data.length() % 16 == 0 else {
    raise InvalidCiphertext
  }
  let padding = data[data.length() - 1].to_int()
  guard padding > 0 && padding <= 16 else { raise InvalidCiphertext }
  for i in (data.length() - padding)..<data.length() {
    guard data[i].to_int() == padding else { raise InvalidCiphertext }
  }
  data[:data.length() - padding].to_owned()
}

///|
fn authenticated_bytes(
  session : String,
  user : String,
  payload : Bytes,
) -> Bytes {
  let out = @buffer.Buffer()
  for text in ["moondiff-token-v1", session, user] {
    let bytes = @utf8.encode(text)
    out.write_int_be(bytes.length())
    out.write_bytes(bytes)
  }
  out.write_bytes(payload)
  out.to_bytes()
}

///|
fn seal(
  key : Bytes,
  session : String,
  user : String,
  plaintext : Bytes,
) -> String raise {
  guard key.length() == 64 else { raise InvalidCiphertext }
  let iv = random_bytes(16)
  let encrypted = @crypto.aes_cbc_encrypt(key[:32], iv, pad(plaintext))
  let out = @buffer.Buffer()
  out.write_byte(b'\x01')
  out.write_bytes(iv)
  out.write_bytes(encrypted)
  let mac = @crypto.hmac(
    @crypto.SHA256::new(),
    key[32:],
    authenticated_bytes(session, user, out.to_bytes()),
  )
  out.write_bytes(Bytes::from_array(mac))
  @base64.encode(out.to_bytes())
}

///|
fn unseal(
  key : Bytes,
  session : String,
  user : String,
  envelope : String,
) -> Bytes raise {
  guard key.length() == 64 else { raise InvalidCiphertext }
  let data = @base64.decode(envelope) catch { _ => raise InvalidCiphertext }
  guard data.length() >= 65 &&
    data[0] == b'\x01' &&
    (data.length() - 49) % 16 == 0 else {
    raise InvalidCiphertext
  }
  let payload = data[:data.length() - 32].to_owned()
  let expected = Bytes::from_array(
    @crypto.hmac(
      @crypto.SHA256::new(),
      key[32:],
      authenticated_bytes(session, user, payload),
    ),
  )
  guard constant_time_equal(expected, data[data.length() - 32:].to_owned()) else {
    raise InvalidCiphertext
  }
  unpad(
    @crypto.aes_cbc_decrypt(key[:32], data[1:17], data[17:data.length() - 32]),
  )
}
