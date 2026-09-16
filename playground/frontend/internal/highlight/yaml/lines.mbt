///|
priv struct SourceLine {
  start : Int
  end : Int
  next : Int
  indent : Int
}

///|
// Keep physical offsets: no newline normalization or scalar folding takes
// place in the highlighter. Only ASCII separators are examined as code units.
fn source_lines(source : String) -> Array[SourceLine] {
  let lines = []
  for start = 0 {
    let mut end = start
    while end < source.length() && source[end] != '\r' && source[end] != '\n' {
      end += 1
    }
    let next = if end < source.length() &&
      source[end] == '\r' &&
      end + 1 < source.length() &&
      source[end + 1] == '\n' {
      end + 2
    } else if end < source.length() {
      end + 1
    } else {
      end
    }
    let content = if start < end && source[start] == '\uFEFF' {
      start + 1
    } else {
      start
    }
    let mut indent = 0
    while content + indent < end && source[content + indent] == ' ' {
      indent += 1
    }
    lines.push({ start: content, end, next, indent, })
    if end == source.length() {
      break
    }
    continue next
  }
  lines
}

///|
fn separated(input : StringView) -> Bool {
  input.is_empty() || input[0] is (' ' | '\t' | '\r' | '\n')
}

///|
fn end_offset(input : StringView) -> Int {
  input.start_offset() + input.length()
}

///|
fn flow_indicator(char : UInt16) -> Bool {
  char is ('[' | ']' | '{' | '}' | ',')
}

///|
fn mapping_colon(input : StringView, flow : Bool) -> Bool {
  !input.is_empty() &&
  input[0] == ':' &&
  (
    separated(input[1:]) ||
    (flow && input.length() > 1 && flow_indicator(input[1]))
  )
}

///|
fn document_marker(input : StringView) -> Bool {
  lexmatch input with longest {
    (re"^(?:---|\.\.\.)", after=rest) => separated(rest)
    _ => false
  }
}

///|
fn comment_offset(line : StringView) -> Int {
  for i = 0; i < line.length(); i = i + 1 {
    if line[i] == '#' && (i == 0 || line[i - 1] is (' ' | '\t')) {
      return i
    }
  }
  line.length()
}
