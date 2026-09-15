///|
fn collect_escapes(
  source : String,
  start : Int,
  end : Int,
  offset : Int,
  spans : Array[HighlightSpan],
) -> Unit {
  let mut plain = start
  for i = start; i < end; {
    if source[i] == '\\' {
      let length = lexmatch source[i:end] {
        (
          re"^(?:\\[0\\tnrb\"']|\\x[0-9a-fA-F]{2}|\\o[0-3][0-7]{2}|\\u[0-9a-fA-F]{4}|\\u[{][0-9a-fA-F]*[}])" as escape,
          after=_,
        ) => escape.length()
        _ => 0
      }
      if length > 0 {
        add_span(spans, offset, plain, i, StringLiteral)
        add_span(spans, offset, i, i + length, Escape)
        plain = i + length
        continue plain
      }
    }
    continue i + 1
  }
  add_span(spans, offset, plain, end, StringLiteral)
}

///|
fn collect_string(
  source : String,
  start : Int,
  end : Int,
  elems : ArrayView[@tokens.InterpElem],
  offset : Int,
  spans : Array[HighlightSpan],
  depth : Int,
) -> Unit {
  let mut cursor = start
  for elem in elems {
    guard elem is InterpSource(expr) else { continue }
    let expr_start = expr.loc.start.cnum
    let expr_end = expr.loc.end.cnum
    guard cursor <= expr_start && expr_start <= expr_end && expr_end <= end else {
      continue
    }
    // The lexer excludes whitespace next to the interpolation delimiters.
    let mut open = expr_start - 2
    while open >= cursor && !(source[open] == '\\' && source[open + 1] == '{') {
      open -= 1
    }
    guard open >= cursor else { continue }
    collect_escapes(source, cursor, open, offset, spans)
    add_span(spans, offset, open, open + 2, Interpolation)
    collect_tokens(
      slice(source, expr_start, expr_end),
      offset + expr_start,
      spans,
      depth + 1,
    )
    let mut close = expr_end
    while close < end &&
          source
          .get_char(close)
          .map(c => c.is_whitespace() || c == '\uFEFF')
          .unwrap_or(false) {
      close += 1
    }
    cursor = if close < end && source[close] == '}' {
      add_span(spans, offset, close, close + 1, Interpolation)
      close + 1
    } else {
      expr_end
    }
  }
  collect_escapes(source, cursor, end, offset, spans)
}
