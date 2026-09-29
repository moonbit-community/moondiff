///|
fn scan_shell_double_part(
  source : String,
  start : Int,
  end : Int,
  opening : Bool,
  expand : Bool,
  state : ShellState,
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
    } else if expand &&
      source[cursor] == '$' &&
      cursor + 1 < end &&
      source[cursor + 1] == '(' {
      add_span(spans, 0, plain, cursor, StringLiteral)
      add_span(spans, 0, cursor, cursor + 2, Interpolation)
      state.substitution_depth += 1
      state.command = true
      cursor += 2
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
fn shell_word_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end &&
        !(source[cursor]
        is (' '
        | '\t'
        | '\''
        | '"'
        | '\\'
        | '$'
        | ';'
        | '&'
        | '|'
        | '<'
        | '>'
        | '('
        | ')')) {
    cursor += 1
  }
  cursor
}

///|
fn scan_shell(
  source : String,
  start : Int,
  end : Int,
  state : ShellState,
  expand : Bool,
  pending : Array[PendingHeredoc],
  spans : Array[HighlightSpan],
) -> Unit {
  let mut cursor = start
  if state.quote is SingleQuoted {
    let (next, closed) = scan_single_continued(source, cursor, end, spans)
    cursor = next
    state.quote = if closed { Unquoted } else { SingleQuoted }
  } else if state.quote is DoubleQuoted {
    let (next, closed) = scan_shell_double_part(
      source, cursor, end, false, expand, state, spans,
    )
    cursor = next
    state.quote = if closed { Unquoted } else { DoubleQuoted }
  }
  while cursor < end {
    let char = source[cursor]
    if char is (' ' | '\t') {
      cursor += 1
      continue
    }
    if char == '#' && (cursor == start || source[cursor - 1] is (' ' | '\t')) {
      add_span(spans, 0, cursor, end, Comment)
      break
    }
    if char == '\'' {
      let (next, closed) = scan_single_quoted(source, cursor, end, spans)
      cursor = next
      state.quote = if closed { Unquoted } else { SingleQuoted }
      continue
    }
    if char == '"' {
      let (next, closed) = scan_shell_double_part(
        source, cursor, end, true, expand, state, spans,
      )
      cursor = next
      state.quote = if closed { Unquoted } else { DoubleQuoted }
      continue
    }
    if char == '\\' {
      let escape_end = Int::min(cursor + 2, end)
      add_span(spans, 0, cursor, escape_end, Escape)
      cursor = escape_end
      continue
    }
    if char == '$' && cursor + 1 < end && source[cursor + 1] == '(' {
      add_span(spans, 0, cursor, cursor + 2, Interpolation)
      state.substitution_depth += 1
      state.command = true
      cursor += 2
      continue
    }
    if char == '$' {
      let next = if expand {
        scan_variable(source, cursor, end, spans)
      } else {
        cursor + 1
      }
      cursor = if next == cursor + 1 { cursor + 1 } else { next }
      continue
    }
    if char == '<' && cursor + 1 < end && source[cursor + 1] == '<' {
      cursor = parse_heredoc(source, cursor, end, true, pending, spans)
      continue
    }
    if char == ')' && state.substitution_depth > 0 {
      add_span(spans, 0, cursor, cursor + 1, Interpolation)
      state.substitution_depth -= 1
      state.command = false
      cursor += 1
      continue
    }
    if char is (';' | '&' | '|' | '<' | '>' | '(' | ')') {
      let operator_start = cursor
      cursor += 1
      if cursor < end &&
        (
          (char == '&' && source[cursor] == '&') ||
          (char == '|' && source[cursor] == '|') ||
          (char == ';' && source[cursor] == ';') ||
          (char == '<' && source[cursor] == '<') ||
          (char == '>' && source[cursor] == '>')
        ) {
        cursor += 1
      }
      add_span(spans, 0, operator_start, cursor, Operator)
      state.command = char is (';' | '&' | '|' | '(')
      continue
    }
    let word_start = cursor
    cursor = shell_word_end(source, cursor, end)
    if cursor == word_start {
      cursor += 1
      continue
    }
    let word = source[word_start:cursor]
    if is_shell_control(word) {
      add_span(spans, 0, word_start, cursor, Control)
      state.command = word is ("then" | "else" | "elif" | "do")
    } else if state.command && word.contains("=") {
      let mut equal = word_start
      while equal < cursor && source[equal] != '=' {
        equal += 1
      }
      let name = source[word_start:equal]
      let valid_name = !name.is_empty() &&
        name[0] is ('a'..='z' | 'A'..='Z' | '_') &&
        variable_name_end(source, word_start, equal) == equal
      if valid_name {
        add_span(spans, 0, word_start, equal, Variable)
        add_span(spans, 0, equal, equal + 1, Operator)
      } else {
        add_span(spans, 0, word_start, cursor, Function)
        state.command = false
      }
    } else if state.command {
      add_span(spans, 0, word_start, cursor, Function)
      state.command = false
    } else if word.has_prefix("-") {
      add_span(spans, 0, word_start, cursor, Attribute)
    } else if is_boolean(word) {
      add_span(spans, 0, word_start, cursor, Boolean)
    } else if is_decimal(word) {
      add_span(spans, 0, word_start, cursor, Number)
    }
  }
}
