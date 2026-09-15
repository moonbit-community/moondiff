///|
fn fence_marker(body : StringView) -> (String, String)? {
  lexmatch body {
    (re"^(?:`{3,}|~{3,})" as marker, after=rest) =>
      Some((marker.to_owned(), rest.trim().to_owned()))
    _ => None
  }
}

///|
fn moonbit_fence(language : String) -> Bool {
  language.is_empty() ||
  (lexmatch language.to_lower() {
    re"^(?:mbt|moonbit)(?:[ \t].*)?$" => true
    _ => false
  })
}

///|
fn collect_docs(
  source : String,
  tokens : ArrayView[@tokens.Triple],
  offset : Int,
  spans : Array[HighlightSpan],
  depth : Int,
) -> Unit {
  let mut fence : (String, Bool)? = None
  let code = StringBuilder()
  let mut code_start = 0
  let mut code_end = 0
  fn flush() -> Unit {
    if !code.is_empty() {
      collect_tokens(code.to_string(), offset + code_start, spans, depth + 1)
      code.reset()
    }
  }
  for (_, start_pos, end_pos) in tokens {
    let start = start_pos.cnum
    let end = end_pos.cnum
    let body = source[start + 3:end].trim()
    match (fence, fence_marker(body)) {
      (None, Some((marker, language))) => {
        fence = Some((marker, moonbit_fence(language)))
        add_span(spans, offset, start, end, Comment)
      }
      (Some((marker, _)), Some((closing, ""))) if closing.has_prefix(marker) => {
        flush()
        fence = None
        add_span(spans, offset, start, end, Comment)
      }
      (Some((_, true)), _) => {
        if code.is_empty() {
          code_start = start
        } else {
          code.write_string(slice(source, code_end, start))
        }
        // Mask only the comment prefix so embedded token offsets still refer
        // to the original file, including indentation and CRLF line endings.
        code.write_string("   ")
        code.write_string(slice(source, start + 3, end))
        code_end = end
        add_span(spans, offset, start, start + 3, Comment)
      }
      _ => add_span(spans, offset, start, end, Comment)
    }
  }
  flush()
}
