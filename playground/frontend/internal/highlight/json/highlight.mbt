///|
priv enum Expect {
  Key
  Colon
  Value
  Comma
}

///|
priv struct Frame {
  object : Bool
  mut expect : Expect
}

///|
/// Scan JSON tokens at their original UTF-16 offsets. Malformed and unfinished
/// input is tolerated so a partially edited file can still be rendered.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  let spans : Array[HighlightSpan] = []
  let frames : Array[Frame] = []
  for i = 0; i < source.length(); {
    let char = source[i]
    if char is (' ' | '\t' | '\r' | '\n') {
      continue i + 1
    }
    // Comments are invalid JSON. Leave the whole invalid region uncolored,
    // including any words or quotes that resemble JSON tokens.
    if char == '/' && i + 1 < source.length() && source[i + 1] == '/' {
      let mut end = i + 2
      while end < source.length() && !(source[end] is ('\r' | '\n')) {
        end += 1
      }
      continue end
    }
    if char == '/' && i + 1 < source.length() && source[i + 1] == '*' {
      let mut end = i + 2
      while end + 1 < source.length() &&
            !(source[end] == '*' && source[end + 1] == '/') {
        end += 1
      }
      continue if end + 1 < source.length() { end + 2 } else { source.length() }
    }
    if char == '"' {
      let key = frames.last() is Some({ object: true, expect: Key, })
      let (end, closed) = scan_string(
        source,
        i,
        if key {
          Variable
        } else {
          StringLiteral
        },
        spans,
      )
      if closed && frames.last() is Some(frame) {
        if key {
          frame.expect = Colon
        } else if frame.expect is Value {
          frame.expect = Comma
        }
      }
      continue end
    }
    if char is ('{' | '[') {
      mark_value(frames)
      frames.push({
        object: char == '{',
        expect: if char == '{' {
          Key
        } else {
          Value
        },
      })
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char is ('}' | ']') {
      if frames.last() is Some(frame) && frame.object == (char == '}') {
        let _ = frames.pop()
      }
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char == ':' {
      if frames.last() is Some(frame) && frame.object && frame.expect is Colon {
        frame.expect = Value
      }
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char == ',' {
      if frames.last() is Some(frame) && frame.expect is Comma {
        frame.expect = if frame.object { Key } else { Value }
      }
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    let end = scan_number(source, i)
    if end > i {
      add_span(spans, 0, i, end, Number)
      mark_value(frames)
      continue end
    }
    let boolean_end = match keyword_end(source, i, "true") {
      Some(end) => Some(end)
      None => keyword_end(source, i, "false")
    }
    if boolean_end is Some(end) {
      add_span(spans, 0, i, end, Boolean)
      mark_value(frames)
      continue end
    }
    if keyword_end(source, i, "null") is Some(end) {
      add_span(spans, 0, i, end, Keyword)
      mark_value(frames)
      continue end
    }
    // Skip an entire malformed atom. Otherwise 01 or truefalse would color a
    // valid-looking suffix even though neither is a JSON token.
    let mut end = i + 1
    while end < source.length() && !atom_separator(source[end]) {
      end += 1
    }
    continue end
  }
  @highlight.SourceHighlights::from_spans(source, spans)
}

///|
fn mark_value(frames : Array[Frame]) -> Unit {
  if frames.last() is Some(frame) && frame.expect is Value {
    frame.expect = Comma
  }
}

///|
fn hex_digit(char : UInt16) -> Bool {
  char is ('0'..='9' | 'a'..='f' | 'A'..='F')
}

///|
fn scan_string(
  source : String,
  start : Int,
  plain_kind : HighlightKind,
  spans : Array[HighlightSpan],
) -> (Int, Bool) {
  let mut i = start + 1
  let mut plain = start
  let mut closed = false
  while i < source.length() {
    let char = source[i]
    if char == '"' {
      i += 1
      closed = true
      break
    }
    if char < ' ' {
      break
    }
    if char == '\\' && i + 1 < source.length() {
      let next = source[i + 1]
      let mut end = i + 2
      let mut valid = next is ('"' | '\\' | '/' | 'b' | 'f' | 'n' | 'r' | 't')
      if next == 'u' &&
        i + 5 < source.length() &&
        hex_digit(source[i + 2]) &&
        hex_digit(source[i + 3]) &&
        hex_digit(source[i + 4]) &&
        hex_digit(source[i + 5]) {
        end = i + 6
        valid = true
      }
      if valid {
        add_span(spans, 0, plain, i, plain_kind)
        add_span(spans, 0, i, end, Escape)
        plain = end
      }
      i = end
    } else {
      i += 1
    }
  }
  add_span(spans, 0, plain, i, plain_kind)
  (i, closed)
}

///|
fn token_end(source : String, index : Int) -> Bool {
  index == source.length() ||
  source[index] is (' ' | '\t' | '\r' | '\n' | ',' | ']' | '}')
}

///|
fn atom_separator(char : UInt16) -> Bool {
  char is (' ' | '\t' | '\r' | '\n' | ',' | ':' | '[' | ']' | '{' | '}' | '"')
}

///|
fn keyword_end(source : String, start : Int, word : String) -> Int? {
  let end = start + word.length()
  if end <= source.length() &&
    source[start:end] == word &&
    token_end(source, end) {
    Some(end)
  } else {
    None
  }
}

///|
fn digit(char : UInt16) -> Bool {
  char is ('0'..='9')
}

///|
fn scan_number(source : String, start : Int) -> Int {
  let size = source.length()
  let mut i = start
  if source[i] == '-' {
    i += 1
  }
  if i == size {
    return start
  }
  if source[i] == '0' {
    i += 1
  } else if source[i] is ('1'..='9') {
    while i < size && digit(source[i]) {
      i += 1
    }
  } else {
    return start
  }
  if i < size && source[i] == '.' {
    i += 1
    if i == size || !digit(source[i]) {
      return start
    }
    while i < size && digit(source[i]) {
      i += 1
    }
  }
  if i < size && source[i] is ('e' | 'E') {
    i += 1
    if i < size && source[i] is ('+' | '-') {
      i += 1
    }
    if i == size || !digit(source[i]) {
      return start
    }
    while i < size && digit(source[i]) {
      i += 1
    }
  }
  if token_end(source, i) {
    i
  } else {
    start
  }
}
