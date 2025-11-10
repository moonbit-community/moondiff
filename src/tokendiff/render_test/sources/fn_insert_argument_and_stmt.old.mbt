///|UUID(ed0506a8-7ab2-419a-8f8c-1aaf5193023f)
pub fn decode(bytes : @bytes.View) -> String raise Malformed {
  let builder = StringBuilder::new(size_hint=bytes.length())
  loop bytes {
    ...
  }
}
