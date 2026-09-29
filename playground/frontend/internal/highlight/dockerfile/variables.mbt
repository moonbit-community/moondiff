///|
fn variable_name_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end &&
        source[cursor] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_') {
    cursor += 1
  }
  cursor
}

///|
fn scan_variable(
  source : String,
  start : Int,
  end : Int,
  spans : Array[HighlightSpan],
) -> Int {
  if start + 1 >= end || source[start] != '$' {
    return start + 1
  }
  if source[start + 1] == '{' {
    add_span(spans, 0, start, start + 2, Interpolation)
    let name_start = start + 2
    let name_end = variable_name_end(source, name_start, end)
    add_span(spans, 0, name_start, name_end, Variable)
    let mut cursor = name_end
    while cursor < end && source[cursor] != '}' {
      if source[cursor] == '$' {
        cursor = scan_variable(source, cursor, end, spans)
      } else if source[cursor]
        is (':' | '-' | '+' | '#' | '%' | '/' | '?' | '=') {
        let operator_start = cursor
        cursor += 1
        while cursor < end &&
              source[cursor] is (':' | '-' | '+' | '#' | '%' | '/' | '?' | '=') {
          cursor += 1
        }
        add_span(spans, 0, operator_start, cursor, Operator)
      } else {
        cursor += 1
      }
    }
    if cursor < end {
      add_span(spans, 0, cursor, cursor + 1, Interpolation)
      cursor += 1
    }
    cursor
  } else if source[start + 1] is ('a'..='z' | 'A'..='Z' | '_') {
    add_span(spans, 0, start, start + 1, Interpolation)
    let name_end = variable_name_end(source, start + 1, end)
    add_span(spans, 0, start + 1, name_end, Variable)
    name_end
  } else if source[start + 1]
    is ('0'..='9' | '@' | '*' | '#' | '?' | '-' | '$' | '!') {
    add_span(spans, 0, start, start + 1, Interpolation)
    add_span(spans, 0, start + 1, start + 2, Variable)
    start + 2
  } else {
    start + 1
  }
}

///|
fn scan_interpolated_text(
  source : String,
  start : Int,
  end : Int,
  kind : HighlightKind,
  expand : Bool,
  spans : Array[HighlightSpan],
) -> Unit {
  let mut cursor = start
  let mut plain = start
  while cursor < end {
    if expand && source[cursor] == '$' {
      add_span(spans, 0, plain, cursor, kind)
      let next = scan_variable(source, cursor, end, spans)
      if next == cursor + 1 {
        cursor += 1
      } else {
        cursor = next
      }
      plain = cursor
    } else {
      cursor += 1
    }
  }
  add_span(spans, 0, plain, end, kind)
}

///|
fn scan_double_quoted(
  source : String,
  start : Int,
  end : Int,
  expand : Bool,
  spans : Array[HighlightSpan],
) -> (Int, Bool) {
  let mut cursor = start + 1
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
    } else if expand && source[cursor] == '$' {
      add_span(spans, 0, plain, cursor, StringLiteral)
      let next = scan_variable(source, cursor, end, spans)
      cursor = if next == cursor + 1 { cursor + 1 } else { next }
      plain = cursor
    } else {
      cursor += 1
    }
  }
  add_span(spans, 0, plain, end, StringLiteral)
  (end, false)
}

///|
fn scan_single_quoted(
  source : String,
  start : Int,
  end : Int,
  spans : Array[HighlightSpan],
) -> (Int, Bool) {
  let mut cursor = start + 1
  while cursor < end && source[cursor] != '\'' {
    cursor += 1
  }
  if cursor < end {
    cursor += 1
  }
  add_span(spans, 0, start, cursor, StringLiteral)
  (cursor, cursor <= end && cursor > start + 1 && source[cursor - 1] == '\'')
}
