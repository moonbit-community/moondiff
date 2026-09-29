///|
fn scan_single_continued(
  source : String,
  start : Int,
  end : Int,
  spans : Array[HighlightSpan],
) -> (Int, Bool) {
  let mut cursor = start
  while cursor < end && source[cursor] != '\'' {
    cursor += 1
  }
  if cursor < end {
    cursor += 1
  }
  add_span(spans, 0, start, cursor, StringLiteral)
  (cursor, cursor > start && source[cursor - 1] == '\'')
}

///|
fn prepare_instruction_segment(
  source : String,
  start : Int,
  end : Int,
  state : InstructionState,
  spans : Array[HighlightSpan],
) -> Int {
  let mut cursor = skip_space(source, start, end)
  if !state.prefix {
    return cursor
  }
  while cursor + 1 < end && source[cursor] == '-' && source[cursor + 1] == '-' {
    cursor = scan_flag(source, cursor, end, spans)
    cursor = skip_space(source, cursor, end)
  }
  if state.root == "ONBUILD" && state.effective == "ONBUILD" {
    let nested_end = ascii_word_end(source, cursor, end)
    if nested_end > cursor && is_instruction(source[cursor:nested_end]) {
      add_span(spans, 0, cursor, nested_end, Keyword)
      state.effective = source[cursor:nested_end].to_upper().to_owned()
      cursor = skip_space(source, nested_end, end)
      while cursor + 1 < end &&
            source[cursor] == '-' &&
            source[cursor + 1] == '-' {
        cursor = scan_flag(source, cursor, end, spans)
        cursor = skip_space(source, cursor, end)
      }
    } else {
      return cursor
    }
  }
  if state.effective == "HEALTHCHECK" {
    let command_end = ascii_word_end(source, cursor, end)
    if command_end > cursor {
      let command = source[cursor:command_end].to_upper()
      if command is ("CMD" | "NONE") {
        add_span(spans, 0, cursor, command_end, Control)
        cursor = skip_space(source, command_end, end)
        if command == "CMD" {
          state.effective = "CMD"
        } else {
          state.prefix = false
          state.mode = Generic
          return cursor
        }
      }
    }
  }
  if cursor < end {
    if supports_json(state.effective) && source[cursor] == '[' {
      state.mode = Json
    } else if is_shell_instruction(state.effective) {
      state.mode = Shell
    } else {
      state.mode = Generic
    }
    state.prefix = false
  }
  cursor
}

///|
fn scan_generic(
  source : String,
  start : Int,
  end : Int,
  state : InstructionState,
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
      source,
      cursor,
      end,
      false,
      true,
      state.shell,
      spans,
    )
    cursor = next
    state.quote = if closed { Unquoted } else { DoubleQuoted }
  }
  while cursor < end {
    let char = source[cursor]
    if char is (' ' | '\t') {
      cursor += 1
    } else if char == '\'' {
      let (next, closed) = scan_single_quoted(source, cursor, end, spans)
      cursor = next
      state.quote = if closed { Unquoted } else { SingleQuoted }
      state.argument_index += 1
    } else if char == '"' {
      let (next, closed) = scan_double_quoted(source, cursor, end, true, spans)
      cursor = next
      state.quote = if closed { Unquoted } else { DoubleQuoted }
      state.argument_index += 1
    } else if char == '$' {
      let next = scan_variable(source, cursor, end, spans)
      cursor = if next == cursor + 1 { cursor + 1 } else { next }
    } else if char == '\\' || char == '`' {
      let escape_end = Int::min(cursor + 2, end)
      add_span(spans, 0, cursor, escape_end, Escape)
      cursor = escape_end
    } else if char == '<' && cursor + 1 < end && source[cursor + 1] == '<' {
      cursor = parse_heredoc(
        source,
        cursor,
        end,
        state.effective == "RUN",
        pending,
        spans,
      )
    } else if char is ('=' | ',') {
      add_span(spans, 0, cursor, cursor + 1, Operator)
      cursor += 1
    } else {
      let word_start = cursor
      cursor = token_end(source, cursor, end)
      if cursor == word_start {
        cursor += 1
        continue
      }
      let word = source[word_start:cursor]
      if state.effective == "FROM" && word.to_upper() == "AS" {
        add_span(spans, 0, word_start, cursor, Control)
      } else if state.effective is ("ENV" | "ARG" | "LABEL") &&
        (state.argument_index == 0 || (cursor < end && source[cursor] == '=')) {
        add_span(spans, 0, word_start, cursor, Variable)
      } else if is_boolean(word) {
        add_span(spans, 0, word_start, cursor, Boolean)
      } else if is_decimal(word) {
        add_span(spans, 0, word_start, cursor, Number)
      }
      state.argument_index += 1
    }
  }
}

///|
fn scan_instruction_segment(
  source : String,
  start : Int,
  end : Int,
  state : InstructionState,
  pending : Array[PendingHeredoc],
  spans : Array[HighlightSpan],
) -> Unit {
  let cursor = prepare_instruction_segment(source, start, end, state, spans)
  match state.mode {
    Undecided => ()
    Json => scan_json(source, cursor, end, state, spans)
    Shell => scan_shell(source, cursor, end, state.shell, true, pending, spans)
    Generic => scan_generic(source, cursor, end, state, pending, spans)
  }
}
