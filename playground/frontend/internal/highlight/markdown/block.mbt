///|
priv struct Prefix {
  content : Int
  indent : Int
  quote_depth : Int
}

///|
fn block_prefix(
  source : String,
  line : SourceLine,
  candidates : Array[Candidate],
) -> Prefix {
  let mut cursor = skip_spaces(source, line.start, line.end, 3)
  let mut base = line.start
  let mut quote_depth = 0
  while cursor < line.end && source[cursor] == '>' {
    quote_depth += 1
    candidate(candidates, cursor, cursor + 1, Control, 65)
    cursor += 1
    if cursor < line.end && source[cursor] == ' ' {
      cursor += 1
    }
    base = cursor
    cursor = skip_spaces(source, cursor, line.end, 3)
  }
  let marker_start = cursor
  let mut marker_end = cursor
  if cursor + 1 < line.end &&
    source[cursor] is ('-' | '+' | '*') &&
    source[cursor + 1] is (' ' | '\t') {
    marker_end = cursor + 1
  } else if cursor < line.end && ascii_digit(source[cursor]) {
    while marker_end < line.end &&
          marker_end - cursor < 9 &&
          ascii_digit(source[marker_end]) {
      marker_end += 1
    }
    if marker_end >= line.end ||
      !(source[marker_end] is ('.' | ')')) ||
      marker_end + 1 >= line.end ||
      !(source[marker_end + 1] is (' ' | '\t')) {
      marker_end = cursor
    } else {
      marker_end += 1
    }
  }
  if marker_end > marker_start {
    candidate(candidates, marker_start, marker_end, Control, 65)
    cursor = marker_end + 1
    if cursor + 2 < line.end &&
      source[cursor] == '[' &&
      source[cursor + 1] is (' ' | 'x' | 'X') &&
      source[cursor + 2] == ']' {
      candidate(candidates, cursor, cursor + 3, Boolean, 85)
      cursor += 3
      if cursor < line.end && source[cursor] is (' ' | '\t') {
        cursor += 1
      }
    }
  }
  { content: cursor, indent: cursor - base, quote_depth, }
}

///|
fn thematic_break(source : String, start : Int, end : Int) -> Bool {
  if start >= end || !(source[start] is ('-' | '*' | '_')) {
    return false
  }
  let marker = source[start]
  let mut count = 0
  for cursor in start..<end {
    if source[cursor] == marker {
      count += 1
    } else if !(source[cursor] is (' ' | '\t')) {
      return false
    }
  }
  count >= 3
}

///|
fn setext_underline(source : String, start : Int, end : Int) -> Bool {
  if start >= end || !(source[start] is ('=' | '-')) {
    return false
  }
  let marker = source[start]
  let mut cursor = start
  while cursor < end && source[cursor] == marker {
    cursor += 1
  }
  cursor > start && trim_space_end(source, cursor, end) == cursor
}

///|
fn table_delimiter(source : String, start : Int, end : Int) -> Bool {
  let mut cursor = start
  let mut dashes = 0
  let mut cells = 0
  while cursor < end {
    while cursor < end && source[cursor] is (' ' | '\t' | '|') {
      cursor += 1
    }
    if cursor < end && source[cursor] == ':' {
      cursor += 1
    }
    dashes = 0
    while cursor < end && source[cursor] == '-' {
      dashes += 1
      cursor += 1
    }
    if dashes < 3 {
      return false
    }
    if cursor < end && source[cursor] == ':' {
      cursor += 1
    }
    while cursor < end && source[cursor] is (' ' | '\t') {
      cursor += 1
    }
    cells += 1
    if cursor < end && source[cursor] == '|' {
      cursor += 1
    } else if cursor < end {
      return false
    }
  }
  cells > 0
}

///|
fn add_table_pipes(
  source : String,
  line : SourceLine,
  candidates : Array[Candidate],
) -> Unit {
  for cursor in line.start..<line.end {
    if source[cursor] == '|' && !escaped(source, cursor, line.start) {
      candidate(candidates, cursor, cursor + 1, Operator, 75)
    }
  }
}

///|
fn add_link_definition(
  source : String,
  start : Int,
  end : Int,
  candidates : Array[Candidate],
) -> Bool {
  if start >= end || source[start] != '[' {
    return false
  }
  match find_char(source, start + 1, end, ']') {
    Some(close) if close + 1 < end && source[close + 1] == ':' => {
      candidate(candidates, start, start + 1, Operator, 80)
      candidate(candidates, start + 1, close, Function, 70)
      candidate(candidates, close, close + 2, Operator, 80)
      let value = skip_spaces(source, close + 2, end, end - close - 2)
      candidate(
        candidates,
        value,
        trim_space_end(source, value, end),
        StringLiteral,
        70,
      )
      true
    }
    _ => false
  }
}

///|
fn strip_fence_body_prefix(
  source : String,
  line : SourceLine,
  indent : Int,
  quote_depth : Int,
  candidates : Array[Candidate],
) -> Int {
  let mut cursor = line.start
  for _ in 0..<quote_depth {
    cursor = skip_spaces(source, cursor, line.end, 3)
    if cursor >= line.end || source[cursor] != '>' {
      return line.start
    }
    candidate(candidates, cursor, cursor + 1, Control, 65)
    cursor += 1
    if cursor < line.end && source[cursor] == ' ' {
      cursor += 1
    }
  }
  let mut removed = 0
  while cursor < line.end && removed < indent && source[cursor] == ' ' {
    cursor += 1
    removed += 1
  }
  cursor
}

///|
fn html_block_tag(source : String, start : Int, end : Int) -> String? {
  if start >= end || source[start] != '<' {
    return None
  }
  let mut cursor = start + 1
  if cursor < end && source[cursor] == '/' {
    cursor += 1
  }
  let name_start = cursor
  while cursor < end &&
        source[cursor] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-') {
    cursor += 1
  }
  if cursor == name_start {
    return if source[start:end].has_prefix("<?") ||
      source[start:end].has_prefix("<![CDATA[") ||
      (
        start + 2 < end &&
        source[start] == '<' &&
        source[start + 1] == '!' &&
        source[start + 2] is ('A'..='Z')
      ) {
      Some("")
    } else {
      None
    }
  }
  let name = source[name_start:cursor].to_owned().to_lower()
  if [
      "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
      "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl",
      "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
      "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe",
      "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol",
      "optgroup", "option", "p", "param", "search", "section", "summary", "table",
      "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul", "script",
      "style", "pre",
    ].contains(name) {
    Some(name)
  } else {
    None
  }
}

///|
fn html_comment_start(source : String, start : Int, end : Int) -> Int? {
  let mut cursor = start
  while cursor + 3 < end {
    if source[cursor:cursor + 4] == "<!--" {
      return Some(cursor)
    }
    cursor += 1
  }
  None
}

///|
fn html_comment_end(source : String, start : Int, end : Int) -> Int? {
  let mut cursor = start
  while cursor + 2 < end {
    if source[cursor:cursor + 3] == "-->" {
      return Some(cursor + 3)
    }
    cursor += 1
  }
  None
}

///|
fn collect_markdown(
  source : String,
  lines : Array[SourceLine],
  candidates : Array[Candidate],
) -> Unit {
  let suppressed = Array::make(lines.length(), false)
  let body : Array[CodeLine] = []
  let mut fence_open = false
  let mut fence_marker : UInt16 = '`'
  let mut fence_size = 0
  let mut fence_indent = 0
  let mut fence_quote_depth = 0
  let mut language = Plain
  let mut html_comment = false
  let mut html_block = false
  let mut html_block_end : String? = None
  for index, line in lines {
    if fence_open {
      let content = strip_fence_body_prefix(
        source, line, fence_indent, fence_quote_depth, candidates,
      )
      match fence_run(source, content, line.end) {
        Some((marker, count)) if marker == fence_marker && count >= fence_size => {
          let rest = skip_spaces(
            source,
            content + count,
            line.end,
            line.end - content - count,
          )
          if rest == line.end {
            add_fence_body(source, body, language, candidates)
            body.clear()
            candidate(candidates, content, content + count, Control, 95)
            suppressed[index] = true
            fence_open = false
            continue
          }
        }
        _ => ()
      }
      body.push({ start: content, end: line.end, })
      suppressed[index] = true
      continue
    }
    if html_block {
      if blank_line(source, line) {
        html_block = false
      } else {
        add_html(source, line.start, line.end, candidates)
        if html_block_end is Some(tag) &&
          source[line.start:line.end].to_owned().to_lower().contains("</\{tag}") {
          html_block = false
          html_block_end = None
        }
      }
      suppressed[index] = true
      continue
    }
    if html_comment {
      match html_comment_end(source, line.start, line.end) {
        Some(finish) => {
          candidate(candidates, line.start, finish, Comment, 130)
          html_comment = false
          scan_inline(source, finish, line.end, candidates)
        }
        None => candidate(candidates, line.start, line.end, Comment, 130)
      }
      suppressed[index] = true
      continue
    }
    match html_comment_start(source, line.start, line.end) {
      Some(comment_start) =>
        match html_comment_end(source, comment_start + 4, line.end) {
          Some(finish) =>
            candidate(candidates, comment_start, finish, Comment, 130)
          None => {
            scan_inline(source, line.start, comment_start, candidates)
            candidate(candidates, comment_start, line.end, Comment, 130)
            html_comment = true
            suppressed[index] = true
          }
        }
      None => ()
    }
    let prefix = block_prefix(source, line, candidates)
    let content = prefix.content
    match fence_run(source, content, line.end) {
      Some((marker, count)) => {
        // Backtick fence info strings cannot themselves contain a backtick.
        let info = source[content + count:line.end].trim().to_owned()
        if marker != '`' || !info.contains("`") {
          fence_open = true
          fence_marker = marker
          fence_size = count
          fence_indent = prefix.indent
          fence_quote_depth = prefix.quote_depth
          language = fence_language(info)
          candidate(candidates, content, content + count, Control, 95)
          if !info.is_empty() {
            candidate(candidates, content + count, line.end, Attribute, 75)
          }
          suppressed[index] = true
          continue
        }
      }
      None => ()
    }
    if content < line.end && source[content] == ' ' {
      candidate(candidates, content + 1, line.end, StringLiteral, 70)
      suppressed[index] = true
      continue
    }
    if html_block_tag(source, content, line.end) is Some(tag) {
      add_html(source, content, line.end, candidates)
      let lower = source[content:line.end].to_owned().to_lower()
      let closes_here = tag is ("script" | "style" | "pre") &&
        lower.contains("</\{tag}")
      html_block = !closes_here
      html_block_end = if !closes_here && tag is ("script" | "style" | "pre") {
        Some(tag)
      } else {
        None
      }
      suppressed[index] = true
      continue
    }
    let mut hashes = content
    while hashes < line.end && hashes - content < 6 && source[hashes] == '#' {
      hashes += 1
    }
    if hashes > content &&
      (hashes == line.end || source[hashes] is (' ' | '\t')) {
      candidate(candidates, content, hashes, Control, 70)
      let title_start = skip_spaces(source, hashes, line.end, line.end - hashes)
      let mut title_end = trim_space_end(source, title_start, line.end)
      let mut closing = title_end
      while closing > title_start && source[closing - 1] == '#' {
        closing -= 1
      }
      if closing < title_end &&
        closing > title_start &&
        source[closing - 1] is (' ' | '\t') {
        candidate(candidates, closing, title_end, Control, 70)
        title_end = trim_space_end(source, title_start, closing)
      }
      candidate(candidates, title_start, title_end, Keyword, 20)
    }
    let setext = index > 0 &&
      setext_underline(source, content, line.end) &&
      !blank_line(source, lines[index - 1]) &&
      !suppressed[index - 1]
    if setext {
      candidate(
        candidates,
        lines[index - 1].start,
        lines[index - 1].end,
        Keyword,
        20,
      )
      candidate(candidates, content, line.end, Control, 70)
      suppressed[index] = true
      continue
    }
    if thematic_break(source, content, line.end) {
      candidate(candidates, content, line.end, Control, 70)
      suppressed[index] = true
      continue
    }
    if table_delimiter(source, content, line.end) &&
      index > 0 &&
      source[lines[index - 1].start:lines[index - 1].end].contains("|") {
      add_table_pipes(source, lines[index - 1], candidates)
      add_table_pipes(source, line, candidates)
      candidate(candidates, content, line.end, Operator, 30)
      suppressed[index] = true
    }
    if add_link_definition(source, content, line.end, candidates) {
      suppressed[index] = true
    }
  }
  if fence_open {
    add_fence_body(source, body, language, candidates)
  }
  // Code spans may cross source lines. Scan each contiguous non-block region
  // once, then let the per-line scanners add the other inline constructs.
  let mut region = 0
  while region < lines.length() {
    while region < lines.length() && suppressed[region] {
      region += 1
    }
    if region == lines.length() {
      break
    }
    let first = region
    while region + 1 < lines.length() && !suppressed[region + 1] {
      region += 1
    }
    add_code_spans(source, lines[first].start, lines[region].end, candidates)
    region += 1
  }
  for index, line in lines {
    if !suppressed[index] {
      scan_inline(source, line.start, line.end, candidates)
    }
  }
}
