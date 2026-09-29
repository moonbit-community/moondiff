///|
fn parse_heredoc(
  source : String,
  start : Int,
  end : Int,
  shell : Bool,
  pending : Array[PendingHeredoc],
  spans : Array[HighlightSpan],
) -> Int {
  let mut cursor = start + 2
  let mut strip_tabs = false
  if cursor < end && source[cursor] == '-' {
    cursor += 1
    strip_tabs = true
  }
  let operator_end = cursor
  cursor = skip_space(source, cursor, end)
  if cursor >= end {
    add_span(spans, 0, start, operator_end, Operator)
    return operator_end
  }
  let delimiter_start = cursor
  let mut expand = true
  let delimiter = if source[cursor] is ('\'' | '"') {
    let quote = source[cursor]
    expand = false
    cursor += 1
    let content_start = cursor
    while cursor < end && source[cursor] != quote {
      cursor += 1
    }
    let delimiter = source[content_start:cursor].to_owned()
    if cursor < end {
      cursor += 1
    }
    delimiter
  } else {
    while cursor < end && !(source[cursor] is (' ' | '\t' | ';' | '&' | '|')) {
      cursor += 1
    }
    source[delimiter_start:cursor].to_owned()
  }
  add_span(spans, 0, start, operator_end, Operator)
  add_span(spans, 0, delimiter_start, cursor, StringLiteral)
  if !delimiter.is_empty() {
    pending.push({
      delimiter,
      strip_tabs,
      expand,
      shell,
      shell_state: ShellState::new(),
    })
  }
  cursor
}

///|
fn heredoc_content_start(
  source : String,
  line : SourceLine,
  strip_tabs : Bool,
) -> Int {
  let mut start = line.start
  if strip_tabs {
    while start < line.end && source[start] == '\t' {
      start += 1
    }
  }
  start
}

///|
fn is_heredoc_delimiter(
  source : String,
  line : SourceLine,
  heredoc : PendingHeredoc,
) -> Bool {
  let start = heredoc_content_start(source, line, heredoc.strip_tabs)
  source[start:line.end] == heredoc.delimiter
}
