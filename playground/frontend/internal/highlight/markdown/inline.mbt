///|
fn find_exact_run(
  source : String,
  start : Int,
  end : Int,
  marker : UInt16,
  count : Int,
) -> Int? {
  let mut cursor = start
  while cursor + count <= end {
    if source[cursor] == marker &&
      (cursor == start || source[cursor - 1] != marker) {
      let mut finish = cursor
      while finish < end && source[finish] == marker {
        finish += 1
      }
      if finish - cursor == count {
        return Some(cursor)
      }
      cursor = finish
    } else {
      cursor += 1
    }
  }
  None
}

///|
fn find_char(source : String, start : Int, end : Int, char : UInt16) -> Int? {
  let mut cursor = start
  while cursor < end {
    if source[cursor] == char {
      return Some(cursor)
    }
    cursor += 1
  }
  None
}

///|
fn escaped(source : String, index : Int, start : Int) -> Bool {
  let mut cursor = index
  while cursor > start && source[cursor - 1] == '\\' {
    cursor -= 1
  }
  (index - cursor) % 2 == 1
}

///|
fn markdown_space(char : UInt16) -> Bool {
  char is (' ' | '\t' | '\r' | '\n')
}

///|
fn emphasis_close(
  source : String,
  start : Int,
  end : Int,
  marker : UInt16,
  count : Int,
) -> Int? {
  let mut cursor = start
  while cursor + count <= end {
    if source[cursor] == marker &&
      !escaped(source, cursor, start) &&
      cursor > start &&
      !markdown_space(source[cursor - 1]) {
      let mut matched = true
      for offset in 1..<count {
        if source[cursor + offset] != marker {
          matched = false
          break
        }
      }
      if matched {
        return Some(cursor)
      }
    }
    cursor += 1
  }
  None
}

///|
fn add_code_spans(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    if source[cursor] != '`' || escaped(source, cursor, start) {
      cursor += 1
      continue
    }
    let opening = cursor
    while cursor < end && source[cursor] == '`' {
      cursor += 1
    }
    let size = cursor - opening
    match find_exact_run(source, cursor, end, '`', size) {
      None => ()
      Some(closing) => {
        candidate(candidates, opening, cursor, Operator, 110)
        candidate(candidates, cursor, closing, StringLiteral, 109)
        candidate(candidates, closing, closing + size, Operator, 110)
        cursor = closing + size
      }
    }
  }
}

///|
fn add_emphasis(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    let marker = source[cursor]
    if !(marker is ('*' | '_' | '~')) || escaped(source, cursor, start) {
      cursor += 1
      continue
    }
    let mut count = 1
    while cursor + count < end && source[cursor + count] == marker {
      count += 1
    }
    let use_count = if marker == '~' {
      if count >= 2 {
        2
      } else {
        0
      }
    } else if count >= 3 {
      3
    } else {
      count
    }
    if use_count == 0 {
      cursor += count
      continue
    }
    if cursor + use_count >= end || markdown_space(source[cursor + use_count]) {
      cursor += count
      continue
    }
    match emphasis_close(source, cursor + use_count, end, marker, use_count) {
      Some(closing) if closing > cursor + use_count => {
        candidate(candidates, cursor, cursor + use_count, Operator, 85)
        candidate(candidates, cursor + use_count, closing, Modifier, 61)
        candidate(candidates, closing, closing + use_count, Operator, 85)
        cursor = closing + use_count
      }
      _ => cursor += count
    }
  }
}

///|
fn add_links(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    let image = source[cursor] == '!' &&
      cursor + 1 < end &&
      source[cursor + 1] == '['
    let open = if image { cursor + 1 } else { cursor }
    if source[open] != '[' || escaped(source, open, start) {
      cursor += 1
      continue
    }
    match find_char(source, open + 1, end, ']') {
      None => cursor += 1
      Some(close) => {
        let after = close + 1
        let mut finish = after
        let mut destination : (Int, Int)? = None
        if after < end && source[after] == '(' {
          match find_char(source, after + 1, end, ')') {
            Some(right) => {
              destination = Some((after + 1, right))
              finish = right + 1
            }
            None => ()
          }
        } else if after < end && source[after] == '[' {
          match find_char(source, after + 1, end, ']') {
            Some(right) => {
              destination = Some((after + 1, right))
              finish = right + 1
            }
            None => ()
          }
        } else {
          // A shortcut reference is useful while its definition is outside a
          // diff hunk, so color it without requiring a resolved definition.
          finish = after
        }
        if finish > after || after == finish {
          if image {
            candidate(candidates, cursor, open, Operator, 80)
          }
          candidate(candidates, open, open + 1, Operator, 80)
          candidate(candidates, open + 1, close, Function, 60)
          candidate(candidates, close, close + 1, Operator, 80)
          if destination is Some((left, right)) {
            candidate(candidates, after, after + 1, Operator, 80)
            candidate(candidates, left, right, StringLiteral, 70)
            candidate(candidates, right, right + 1, Operator, 80)
          }
          cursor = Int::max(close + 1, finish)
        }
      }
    }
  }
}

///|
fn url_end(source : String, start : Int, end : Int) -> Int {
  let mut cursor = start
  while cursor < end &&
        !(source[cursor] is (' ' | '\t' | '<' | '>' | '"' | '\'' | '`')) {
    cursor += 1
  }
  while cursor > start &&
        source[cursor - 1] is ('.' | ',' | ':' | ';' | '!' | '?') {
    cursor -= 1
  }
  cursor
}

///|
fn add_urls(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    let rest = source[cursor:end]
    let prefix = if rest.has_prefix("https://") {
      8
    } else if rest.has_prefix("http://") {
      7
    } else if rest.has_prefix("www.") {
      4
    } else {
      0
    }
    if prefix > 0 &&
      (
        cursor == start ||
        !(source[cursor - 1] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_'))
      ) {
      let finish = url_end(source, cursor + prefix, end)
      if finish > cursor + prefix {
        candidate(candidates, cursor, finish, StringLiteral, 75)
        cursor = finish
        continue
      }
    }
    if source[cursor] == '@' && cursor > start && cursor + 1 < end {
      let mut left = cursor
      while left > start &&
            source[left - 1]
            is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '_' | '%' | '+' | '-') {
        left -= 1
      }
      let mut right = cursor + 1
      let mut dot = false
      while right < end &&
            source[right] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-') {
        if source[right] == '.' {
          dot = true
        }
        right += 1
      }
      if left < cursor && right > cursor + 1 && dot {
        candidate(candidates, left, right, StringLiteral, 75)
        cursor = right
        continue
      }
    }
    cursor += 1
  }
}

///|
fn add_angle_autolinks(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    if source[cursor] != '<' {
      cursor += 1
      continue
    }
    match find_char(source, cursor + 1, end, '>') {
      None => cursor += 1
      Some(close) => {
        let body = source[cursor + 1:close]
        let automatic = body.has_prefix("http://") ||
          body.has_prefix("https://") ||
          body.has_prefix("mailto:") ||
          body.contains("@")
        if automatic && !body.contains(" ") && !body.contains("\t") {
          candidate(candidates, cursor, cursor + 1, Operator, 107)
          candidate(candidates, cursor + 1, close, StringLiteral, 106)
          candidate(candidates, close, close + 1, Operator, 107)
          cursor = close + 1
        } else {
          cursor += 1
        }
      }
    }
  }
}

///|
fn add_escapes_entities(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    if source[cursor] == '\\' && cursor + 1 < end {
      if source[cursor + 1]
        is ('!'
        | '"'
        | '#'
        | '$'
        | '%'
        | '&'
        | '\''
        | '('
        | ')'
        | '*'
        | '+'
        | ','
        | '-'
        | '.'
        | '/'
        | ':'
        | ';'
        | '<'
        | '='
        | '>'
        | '?'
        | '@'
        | '['
        | '\\'
        | ']'
        | '^'
        | '_'
        | '`'
        | '{'
        | '|'
        | '}'
        | '~') {
        candidate(candidates, cursor, cursor + 2, Escape, 120)
        cursor += 2
        continue
      }
    }
    if source[cursor] == '&' {
      let mut finish = cursor + 1
      if finish < end && source[finish] == '#' {
        finish += 1
        if finish < end && source[finish] is ('x' | 'X') {
          finish += 1
          while finish < end &&
                source[finish] is ('0'..='9' | 'a'..='f' | 'A'..='F') {
            finish += 1
          }
        } else {
          while finish < end && ascii_digit(source[finish]) {
            finish += 1
          }
        }
      } else {
        while finish < end &&
              source[finish] is ('a'..='z' | 'A'..='Z' | '0'..='9') {
          finish += 1
        }
      }
      if finish > cursor + 1 && finish < end && source[finish] == ';' {
        candidate(candidates, cursor, finish + 1, Escape, 120)
        cursor = finish + 1
        continue
      }
    }
    cursor += 1
  }
  let trimmed = trim_space_end(source, start, end)
  if end - trimmed >= 2 {
    candidate(candidates, end - 2, end, Escape, 120)
  } else if trimmed > start && source[trimmed - 1] == '\\' {
    candidate(candidates, trimmed - 1, trimmed, Escape, 120)
  }
}

///|
fn add_html(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  let mut cursor = start
  while cursor < end {
    if source[cursor] != '<' {
      cursor += 1
      continue
    }
    if source[cursor:end].has_prefix("<!--") {
      let mut finish = cursor + 4
      while finish + 2 < end && source[finish:finish + 3] != "-->" {
        finish += 1
      }
      finish = if finish + 2 < end { finish + 3 } else { end }
      candidate(candidates, cursor, finish, Comment, 130)
      cursor = finish
      continue
    }
    let mut name_start = cursor + 1
    if name_start < end && source[name_start] == '/' {
      name_start += 1
    }
    if name_start >= end || !(source[name_start] is ('a'..='z' | 'A'..='Z')) {
      cursor += 1
      continue
    }
    let mut name_end = name_start + 1
    while name_end < end &&
          source[name_end] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-') {
      name_end += 1
    }
    match find_char(source, name_end, end, '>') {
      None => cursor += 1
      Some(close) => {
        candidate(candidates, cursor, name_end, Type, 100)
        if close > name_end {
          let mut attr = name_end
          while attr < close {
            while attr < close && source[attr] is (' ' | '\t' | '/') {
              attr += 1
            }
            let attr_start = attr
            while attr < close &&
                  source[attr]
                  is ('a'..='z' | 'A'..='Z' | '0'..='9' | ':' | '_' | '-') {
              attr += 1
            }
            candidate(candidates, attr_start, attr, Attribute, 101)
            while attr < close && !(source[attr] is (' ' | '\t')) {
              attr += 1
            }
          }
        }
        candidate(candidates, close, close + 1, Type, 100)
        cursor = close + 1
      }
    }
  }
}

///|
fn scan_inline(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Unit {
  add_emphasis(source, start, end, candidates)
  add_links(source, start, end, candidates)
  add_urls(source, start, end, candidates)
  add_html(source, start, end, candidates)
  add_angle_autolinks(source, start, end, candidates)
  add_code_spans(source, start, end, candidates)
  add_escapes_entities(source, start, end, candidates)
}
