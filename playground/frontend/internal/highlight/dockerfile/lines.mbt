///|
priv struct SourceLine {
  start : Int
  end : Int
}

///|
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
    lines.push({ start, end, })
    if end == source.length() {
      break
    }
    continue next
  }
  lines
}

///|
fn skip_space(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end && source[cursor] is (' ' | '\t') {
    cursor += 1
  }
  cursor
}

///|
fn trim_space_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = end
  while cursor > start && source[cursor - 1] is (' ' | '\t') {
    cursor -= 1
  }
  cursor
}

///|
fn ascii_word_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end &&
        source[cursor] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-') {
    cursor += 1
  }
  cursor
}

///|
fn token_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end &&
        !(source[cursor]
        is (' ' | '\t' | ',' | '=' | '$' | '\\' | '`' | '\'' | '"' | '<')) {
    cursor += 1
  }
  cursor
}
