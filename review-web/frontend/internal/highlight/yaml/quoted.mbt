///|
const RE_ESCAPE : Regex = re"\\[0abtnvfre \t\"/\\N_LP]|\\x[0-9a-fA-F]{2}|\\u[0-9a-fA-F]{4}|\\U[0-9a-fA-F]{8}|\\(?:\r\n|[\r\n])"

///|
fn collect_double_quoted(
  input : StringView,
  spans : Array[HighlightSpan],
) -> StringView {
  let mut plain = input.start_offset()
  let rest = for input = input[1:] {
    lexmatch input with longest {
      (re"^" + RE_ESCAPE, after=rest) => {
        add_span(spans, 0, plain, input.start_offset(), StringLiteral)
        add_span(spans, 0, input.start_offset(), rest.start_offset(), Escape)
        plain = rest.start_offset()
        continue rest
      }
      (re"^\"", after=rest) => break rest
      (re"^[^\"\\]+", after=rest) => continue rest
      // Keep incomplete/unknown escapes in the string, including a Unicode
      // character after a backslash. A missing quote safely extends to EOF.
      (re"^\\[^\r\n]?", after=rest) => continue rest
      re"^$" => break input
    }
  }
  add_span(spans, 0, plain, rest.start_offset(), StringLiteral)
  rest
}

///|
fn collect_single_quoted(
  input : StringView,
  spans : Array[HighlightSpan],
) -> StringView {
  let mut plain = input.start_offset()
  let rest = for input = input[1:] {
    lexmatch input with longest {
      (re"^''", after=rest) => {
        add_span(spans, 0, plain, input.start_offset(), StringLiteral)
        add_span(spans, 0, input.start_offset(), rest.start_offset(), Escape)
        plain = rest.start_offset()
        continue rest
      }
      (re"^'", after=rest) => break rest
      (re"^[^']+", after=rest) => continue rest
      re"^$" => break input
    }
  }
  add_span(spans, 0, plain, rest.start_offset(), StringLiteral)
  rest
}

///|
fn followed_by_colon(input : StringView, flow : Bool, quoted : Bool) -> Bool {
  let rest = input.trim_start(chars=" \t")
  mapping_colon(rest, flow) ||
  (flow && quoted && !rest.is_empty() && rest[0] == ':')
}
