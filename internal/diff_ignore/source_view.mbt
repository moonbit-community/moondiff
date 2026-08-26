///|
// One original line with filtered characters removed from comparison.
// `ignored` is indexed by Unicode scalar value, matching CST location columns.
pub struct SourceLineView {
  source : String
  visible : String
  ignored : Array[Bool]
  has_ignored : Bool
}

///|
// One source with selected characters hidden during comparison. Visible line
// indexes are dense; `source_indices` maps them back to local original lines,
// while `visible_indices` is the inverse. Slices retain a global line offset
// so CST spans can be mapped directly.
pub struct SourceView {
  source_lines : Array[String]
  line_views : Array[SourceLineView]
  lines : Array[String]
  source_indices : Array[Int]
  visible_indices : Array[Int]
  source_line_offset : Int
}

///|
fn source_line_is_blank(line : String) -> Bool {
  for ch in line {
    if !ch.is_whitespace() {
      return false
    }
  }
  true
}

///|
fn mark_ignored_range(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  line : Int,
  start : Int,
  end_ : Int,
) -> Unit {
  guard ignored.get(line) is Some(mask) else { return }
  let start = @cmp.minimum(@cmp.maximum(start, 0), mask.length())
  let end_ = @cmp.minimum(@cmp.maximum(end_, start), mask.length())
  touched[line] = true
  for index in start..<end_ {
    mask[index] = true
  }
}

///|
fn mark_ignored_line(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  line : Int,
) -> Unit {
  guard ignored.get(line) is Some(mask) else { return }
  touched[line] = true
  for index in 0..<mask.length() {
    mask[index] = true
  }
}

///|
fn mark_location(
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  range : @basic.Location,
) -> Unit {
  let start_line = range.start.lnum - 1
  let end_line = range.end.lnum - 1
  let start_col = @cmp.maximum(range.start.column() - 1, 0)
  let end_col = @cmp.maximum(range.end.column() - 1, 0)
  if start_line == end_line {
    mark_ignored_range(ignored, touched, start_line, start_col, end_col)
    return
  }
  if ignored.get(start_line) is Some(mask) {
    mark_ignored_range(ignored, touched, start_line, start_col, mask.length())
  }
  for line in (start_line + 1)..<end_line {
    mark_ignored_line(ignored, touched, line)
  }
  if end_col > 0 {
    mark_ignored_range(ignored, touched, end_line, 0, end_col)
  }
}

///|
fn mark_separator_lines(
  source_lines : ArrayView[String],
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  range : @basic.Location,
) -> Unit {
  let first = range.start.lnum - 1
  let end_line = range.end.lnum - 1
  let end_col = @cmp.maximum(range.end.column() - 1, 0)
  let last = if end_col == 0 && end_line > first {
    end_line - 1
  } else {
    end_line
  }
  let mut before = first - 1
  while before >= 0 &&
        source_lines.get(before) is Some(line) &&
        source_line_is_blank(line) {
    mark_ignored_line(ignored, touched, before)
    before -= 1
  }
  let mut after = last + 1
  while after < source_lines.length() &&
        source_line_is_blank(source_lines[after]) {
    mark_ignored_line(ignored, touched, after)
    after += 1
  }
}

///|
// The upstream lexer advances recursively once per lexical item. Keep the
// safety decision in this lower-level package so comment view and token
// diff use the same conservative threshold.
const LEXER_COMPLEXITY_LIMIT : Int = 256

///|
fn fallback_char_class(c : Char) -> Int {
  if c.is_whitespace() {
    0
  } else if c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    c == '_' ||
    !c.is_ascii() {
    1
  } else {
    2
  }
}

///|
pub fn lexer_complexity_within_limit(line : String) -> Bool {
  let mut offset = 0
  let mut pieces = 0
  while offset < line.length() {
    guard line.get_char(offset) is Some(c) else { break }
    let cls = fallback_char_class(c)
    pieces += 1
    if pieces > LEXER_COMPLEXITY_LIMIT {
      return false
    }
    offset += c.utf16_len()
    if cls != 2 {
      while line.get_char(offset) is Some(next) &&
            fallback_char_class(next) == cls {
        offset += next.utf16_len()
      }
    }
  }
  true
}

///|
// Mirror enough quote handling to locate a real line comment without invoking
// the recursive lexer on an externally supplied, unusually complex line.
fn fallback_source_comment_start(line : String) -> Int? {
  let trimmed = line.trim_start()
  if trimmed.has_prefix("#|") || trimmed.has_prefix("$|") {
    return None
  }
  let mut quote : Char? = None
  let mut escaped = false
  let mut offset = 0
  while offset < line.length() {
    guard line.get_char(offset) is Some(char) else { break }
    if quote is Some(delimiter) {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == delimiter {
        quote = None
      }
    } else if char is ('"' | '\'') {
      quote = Some(char)
    } else if char == '/' && line.get_char(offset + 1) == Some('/') {
      return Some(offset)
    }
    offset += char.utf16_len()
  }
  None
}

///|
fn source_comment_start(line : String) -> Int? {
  if !lexer_complexity_within_limit(line) {
    return fallback_source_comment_start(line)
  }
  let result = @lexer.tokens_from_string_with_utf16_location(comment=true, line)
  for triple in result.tokens {
    let (token, start, _) = triple
    if token is COMMENT(_) {
      return Some(start.cnum)
    }
  }
  None
}

///|
fn mark_comment(
  source_lines : ArrayView[String],
  source_chars : ArrayView[Array[Char]],
  ignored : Array[Array[Bool]],
  touched : Array[Bool],
  line_index : Int,
) -> Unit {
  let line = source_lines[line_index]
  if source_line_is_blank(line) {
    mark_ignored_line(ignored, touched, line_index)
    return
  }
  guard source_comment_start(line) is Some(comment_start) else { return }
  let prefix = line.view(end_offset=comment_start).to_owned()
  let code = prefix.trim_end().to_owned()
  mark_ignored_range(
    ignored,
    touched,
    line_index,
    code.to_array().length(),
    source_chars[line_index].length(),
  )
}

///|
// Whitespace directly beside filtered syntax belongs to the ignored fragment.
// In particular, this removes indentation and spacing before a same-line
// retained suffix without consuming that suffix.
fn expand_ignored_line_whitespace(
  chars : ArrayView[Char],
  ignored : Array[Bool],
) -> Unit {
  let mut start = 0
  while start < chars.length() {
    if !chars[start].is_whitespace() {
      start += 1
      continue
    }
    let mut end_ = start + 1
    while end_ < chars.length() && chars[end_].is_whitespace() {
      end_ += 1
    }
    if (start > 0 && ignored[start - 1]) ||
      (end_ < chars.length() && ignored[end_]) {
      for index in start..<end_ {
        ignored[index] = true
      }
    }
    start = end_
  }
}

///|
fn SourceLineView::fully_ignored(self : SourceLineView) -> Bool {
  self.has_ignored && self.ignored.all(value => value)
}

///|
fn source_view_from_lines(
  line_views : Array[SourceLineView],
  source_line_offset : Int,
) -> SourceView {
  let source_lines : Array[String] = []
  let lines : Array[String] = []
  let source_indices : Array[Int] = []
  let visible_indices = Array::make(line_views.length(), -1)
  for source_index, line in line_views {
    source_lines.push(line.source)
    if !line.fully_ignored() {
      visible_indices[source_index] = lines.length()
      lines.push(line.visible)
      source_indices.push(source_index)
    }
  }
  {
    source_lines,
    line_views,
    lines,
    source_indices,
    visible_indices,
    source_line_offset,
  }
}

///|
fn make_source_view(
  source_lines : Array[String],
  ignored_ranges : ArrayView[@basic.Location],
  ignore_comments : Bool,
) -> SourceView {
  let source_chars : Array[Array[Char]] = source_lines.map(line => {
    line.to_array()
  })
  let ignored : Array[Array[Bool]] = source_chars.map(chars => {
    Array::make(chars.length(), false)
  })
  let touched = Array::make(source_lines.length(), false)
  for range in ignored_ranges {
    mark_location(ignored, touched, range)
    mark_separator_lines(source_lines, ignored, touched, range)
  }
  if ignore_comments {
    for line_index in 0..<source_lines.length() {
      mark_comment(source_lines, source_chars, ignored, touched, line_index)
    }
  }
  let line_views : Array[SourceLineView] = []
  for index, chars in source_chars {
    let mask = ignored[index]
    expand_ignored_line_whitespace(chars, mask)
    let visible_chars : Array[Char] = []
    for char_index, ch in chars {
      if !mask[char_index] {
        visible_chars.push(ch)
      }
    }
    line_views.push({
      source: source_lines[index],
      visible: String::from_array(visible_chars),
      ignored: mask,
      has_ignored: touched[index],
    })
  }
  source_view_from_lines(line_views, 0)
}

///|
/// Build a source-faithful comparison view from a complete source file.
/// Ranges use MoonBit lexer locations; comments and blank lines can be excluded
/// by the same view so structural and lexical callers share one policy.
pub fn SourceView::from_source(
  source : String,
  ignored_ranges? : ArrayView[@basic.Location] = [],
  ignore_comments? : Bool = false,
) -> SourceView {
  make_source_view(
    if source == "" {
      []
    } else {
      @source_text.split_lines(source)
    },
    ignored_ranges,
    ignore_comments,
  )
}

///|
/// Build a view from an existing line array. This is used by token diff,
/// whose public input distinguishes an empty array from a source string.
pub fn SourceView::from_lines(
  lines : ArrayView[String],
  ignore_comments? : Bool = false,
) -> SourceView {
  make_source_view(lines.to_owned(), [], ignore_comments)
}

///|
pub fn SourceView::lines(self : SourceView) -> ArrayView[String] {
  self.lines
}

///|
pub fn SourceView::source(self : SourceView) -> String {
  self.lines.join("\n")
}

///|
pub fn SourceView::slice(
  self : SourceView,
  source_start : Int,
  source_len : Int,
) -> SourceView {
  let local_start = @cmp.minimum(
    @cmp.maximum(source_start - self.source_line_offset, 0),
    self.line_views.length(),
  )
  let local_end = @cmp.minimum(
    local_start + @cmp.maximum(source_len, 0),
    self.line_views.length(),
  )
  source_view_from_lines(
    self.line_views[local_start:local_end].to_owned(),
    self.source_line_offset + local_start,
  )
}

///|
fn span_character_bounds(
  span : @span.SingleLineSpan,
  line_len : Int,
) -> (Int, Int) {
  let start = if span.start_col == 0 {
    0
  } else {
    @cmp.maximum(span.start_col - 1, 0)
  }
  let end_ = if span.start_col == 0 { span.end_col } else { span.end_col - 1 }
  (
    @cmp.minimum(start, line_len),
    @cmp.minimum(@cmp.maximum(end_, start), line_len),
  )
}

///|
fn visible_boundary(line : SourceLineView, boundary : Int) -> Int {
  let mut visible = 0
  for index in 0..<@cmp.minimum(boundary, line.ignored.length()) {
    if !line.ignored[index] {
      visible += 1
    }
  }
  visible
}

///|
pub fn SourceView::map_span(
  self : SourceView,
  span : @span.SingleLineSpan,
) -> @span.SingleLineSpan? {
  let source_index = span.line - 1 - self.source_line_offset
  guard self.visible_indices.get(source_index) is Some(visible_index) &&
    visible_index >= 0 &&
    self.line_views.get(source_index) is Some(line) else {
    return None
  }
  let (start, end_) = span_character_bounds(span, line.ignored.length())
  if start >= end_ {
    return None
  }
  for index in start..<end_ {
    if line.ignored[index] {
      return None
    }
  }
  let visible_start = visible_boundary(line, start)
  let visible_end = visible_boundary(line, end_)
  if visible_start >= visible_end {
    None
  } else {
    Some({
      line: visible_index + 1,
      start_col: visible_start + 1,
      end_col: visible_end + 1,
    })
  }
}
