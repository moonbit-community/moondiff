///|
fn collect_string(
  input : StringView,
  quote : Char,
  start : Int,
  spans : Array[HighlightSpan],
) -> StringView {
  let mut plain = start
  let rest = for input = input {
    lexmatch input with longest {
      (re"^" + RE_ESCAPE, after=rest) => {
        add_span(spans, 0, plain, input.start_offset(), StringLiteral)
        add_span(spans, 0, input.start_offset(), rest.start_offset(), Escape)
        plain = rest.start_offset()
        continue rest
      }
      (re"^['\"]" as char, after=rest) =>
        if char == quote {
          break rest
        } else {
          continue rest
        }
      (re"^[^\\\r\n'\"]+", after=rest) => continue rest
      // Unknown escapes consume the following character without starting a
      // new escape or closing the literal. Valid escapes win equal-length ties.
      (re"^\\[^\r\n]?", after=rest) => continue rest
      // Splicing already removed escaped newlines; recover at an unescaped
      // newline without consuming it, so the outer lexer can reset directives.
      (re"^" + RE_NEWLINE, after=_) => break input
      re"^$" => break input
    }
  }
  add_span(spans, 0, plain, rest.start_offset(), StringLiteral)
  rest
}

///|
fn collect_header(
  input : StringView,
  spans : Array[HighlightSpan],
) -> StringView? {
  lexmatch input with longest {
    (re"^" + RE_HEADER, after=rest) => {
      add_span(
        spans,
        0,
        input.start_offset(),
        rest.start_offset(),
        StringLiteral,
      )
      Some(rest)
    }
    _ => None
  }
}
