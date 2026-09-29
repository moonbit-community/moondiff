///|
fn scan_json_string_part(
  source : String,
  start : Int,
  end : Int,
  opening : Bool,
  spans : Array[HighlightSpan],
) -> (Int, Bool) {
  let mut cursor = if opening { start + 1 } else { start }
  let mut plain = start
  while cursor < end {
    if source[cursor] == '"' {
      cursor += 1
      add_span(spans, 0, plain, cursor, StringLiteral)
      return (cursor, true)
    }
    if source[cursor] == '\\' {
      add_span(spans, 0, plain, cursor, StringLiteral)
      let escape_end = Int::min(cursor + 2, end)
      add_span(spans, 0, cursor, escape_end, Escape)
      cursor = escape_end
      plain = cursor
    } else {
      cursor += 1
    }
  }
  add_span(spans, 0, plain, end, StringLiteral)
  (end, false)
}

///|
fn scan_json(
  source : String,
  start : Int,
  end : Int,
  state : InstructionState,
  spans : Array[HighlightSpan],
) -> Unit {
  let mut cursor = start
  if state.json_string {
    let (next, closed) = scan_json_string_part(
      source, cursor, end, false, spans,
    )
    cursor = next
    state.json_string = !closed
  }
  while cursor < end {
    let char = source[cursor]
    if char is (' ' | '\t') {
      cursor += 1
    } else if char == '"' {
      let (next, closed) = scan_json_string_part(
        source, cursor, end, true, spans,
      )
      cursor = next
      state.json_string = !closed
    } else if char is ('[' | ']' | '{' | '}' | ',' | ':') {
      add_span(spans, 0, cursor, cursor + 1, Operator)
      cursor += 1
    } else {
      let word_start = cursor
      while cursor < end &&
            !(source[cursor] is (' ' | '\t' | '[' | ']' | '{' | '}' | ',' | ':')) {
        cursor += 1
      }
      let word = source[word_start:cursor]
      if word is ("true" | "false") {
        add_span(spans, 0, word_start, cursor, Boolean)
      } else if word == "null" {
        add_span(spans, 0, word_start, cursor, Keyword)
      } else if is_decimal(word) ||
        (word.has_prefix("-") && is_decimal(word[1:])) {
        add_span(spans, 0, word_start, cursor, Number)
      }
    }
  }
}
