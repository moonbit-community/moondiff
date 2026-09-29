///|
fn parser_directive(
  source : String,
  line : SourceLine,
  spans : Array[HighlightSpan],
) -> (String, Int, Int)? {
  let mut cursor = skip_space(source, line.start, line.end)
  if cursor >= line.end || source[cursor] != '#' {
    return None
  }
  let hash = cursor
  cursor = skip_space(source, cursor + 1, line.end)
  let key_start = cursor
  cursor = ascii_word_end(source, cursor, line.end)
  let key_end = cursor
  let key = source[key_start:key_end].to_lower()
  if !(key is ("syntax" | "escape" | "check")) {
    return None
  }
  cursor = skip_space(source, cursor, line.end)
  if cursor >= line.end || source[cursor] != '=' {
    return None
  }
  let equal = cursor
  let value_start = skip_space(source, cursor + 1, line.end)
  add_span(spans, 0, hash, hash + 1, Control)
  add_span(spans, 0, key_start, key_end, Attribute)
  add_span(spans, 0, equal, equal + 1, Operator)
  if key == "syntax" {
    add_span(spans, 0, value_start, line.end, StringLiteral)
  } else if key == "escape" {
    add_span(spans, 0, value_start, line.end, Escape)
  } else {
    let mut part = value_start
    let mut value = false
    for i = value_start; i <= line.end; i = i + 1 {
      if i == line.end || source[i] is ('=' | ',' | ';') {
        if part < i {
          let word = source[part:i]
          let kind : HighlightKind = if value && word is ("true" | "false") {
            Boolean
          } else if value {
            AttributeParameter
          } else {
            Attribute
          }
          add_span(spans, 0, part, i, kind)
        }
        if i < line.end {
          add_span(spans, 0, i, i + 1, Operator)
          value = if source[i] == '=' {
            true
          } else if source[i] == ';' {
            false
          } else {
            value
          }
          part = i + 1
        }
      }
    }
  }
  Some((key.to_owned(), value_start, line.end))
}
