///|UUID(ed0506a8-7ab2-419a-8f8c-1aaf5193023f)
pub fn decode(
  bytes : @bytes.View,
  ignore_bom? : Bool = false,
) -> String raise Malformed {
  let bytes = if ignore_bom && bytes is [.. "\xef\xbb\xbf", .. rest] {
    rest
  } else {
    bytes
  }
  let builder = StringBuilder::new(size_hint=bytes.length())
  loop bytes {
    ...
  }
}
