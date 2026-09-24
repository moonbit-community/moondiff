///|
priv enum Mode {
  Template(Bool)
  Interpolation(Int)
}

///|
priv enum TemplateStop {
  Closed
  Expression
  EndOfSource
}

///|
/// Highlight JavaScript source with a tolerant lexical scan. All offsets are
/// UTF-16 code units in the original source; indexing applies shared budgets.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  let spans : Array[HighlightSpan] = []
  let modes : Array[Mode] = []
  let parens : Array[Bool] = []
  let braces : Array[Bool] = []
  let mut can_start_expression = true
  let mut control_paren = false
  let mut pending_block = true
  let mut name_kind : HighlightKind? = None
  for i = 0; i < source.length(); {
    if modes.last() is Some(Template(opening)) {
      let (end, stop) = scan_template(source, i, opening, spans)
      match stop {
        Closed => {
          let _ = modes.pop()
          can_start_expression = false
          pending_block = false
        }
        Expression => {
          modes[modes.length() - 1] = Template(false)
          modes.push(Interpolation(0))
          can_start_expression = true
          pending_block = false
        }
        EndOfSource => ()
      }
      continue end
    }
    let char = source[i]
    if is_space(char) {
      continue i + 1
    }
    if modes.last() is Some(Interpolation(0)) && char == '}' {
      add_span(spans, 0, i, i + 1, Interpolation)
      let _ = modes.pop()
      can_start_expression = false
      pending_block = false
      continue i + 1
    }
    if char == '/' && i + 1 < source.length() && source[i + 1] == '/' {
      let mut end = i + 2
      while end < source.length() && !is_newline(source[end]) {
        end += 1
      }
      add_span(spans, 0, i, end, Comment)
      continue end
    }
    if char == '/' && i + 1 < source.length() && source[i + 1] == '*' {
      let mut end = i + 2
      while end + 1 < source.length() &&
            !(source[end] == '*' && source[end + 1] == '/') {
        end += 1
      }
      if end + 1 < source.length() {
        end += 2
      } else {
        end = source.length()
      }
      add_span(spans, 0, i, end, Comment)
      continue end
    }
    if char is ('\'' | '"') {
      let end = scan_quote(source, i, spans)
      can_start_expression = false
      control_paren = false
      pending_block = false
      continue end
    }
    if char == '`' {
      modes.push(Template(true))
      control_paren = false
      pending_block = false
      continue i
    }
    if char == '/' && can_start_expression {
      let end = scan_regex(source, i)
      add_span(spans, 0, i, end, StringLiteral)
      can_start_expression = false
      control_paren = false
      pending_block = false
      continue end
    }
    if ascii_digit(char) ||
      (char == '.' && i + 1 < source.length() && ascii_digit(source[i + 1])) {
      let end = scan_number(source, i)
      add_span(spans, 0, i, end, Number)
      can_start_expression = false
      control_paren = false
      pending_block = false
      continue end
    }
    if identifier_start(char) {
      let mut end = i + 1
      while end < source.length() && identifier_part(source[end]) {
        end += 1
      }
      let word = source[i:end]
      let mut kind = word_kind(word)
      if name_kind is Some(expected) && kind is Variable {
        kind = expected
      } else if kind is Variable && following_paren(source, end) {
        kind = Function
      }
      add_span(spans, 0, i, end, kind)
      name_kind = match word {
        "function" => Some(Function)
        "class" | "extends" | "new" => Some(Type)
        _ => None
      }
      control_paren = word
        is ("if" | "while" | "for" | "with" | "switch" | "catch")
      pending_block = word is ("else" | "try" | "finally" | "do")
      can_start_expression = word_allows_expression(word, kind)
      continue end
    }
    if char == '(' {
      parens.push(control_paren)
      control_paren = false
      pending_block = false
      can_start_expression = true
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char == ')' {
      let control = parens.pop().unwrap_or(false)
      can_start_expression = control
      pending_block = control
      control_paren = false
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char == '{' {
      braces.push(pending_block || !can_start_expression)
      if modes.last() is Some(Interpolation(depth)) {
        modes[modes.length() - 1] = Interpolation(depth + 1)
      }
      can_start_expression = true
      control_paren = false
      pending_block = false
      name_kind = None
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    if char == '}' {
      if modes.last() is Some(Interpolation(depth)) {
        modes[modes.length() - 1] = Interpolation(depth - 1)
      }
      let block = braces.pop().unwrap_or(false)
      can_start_expression = block
      control_paren = false
      pending_block = block
      add_span(spans, 0, i, i + 1, Operator)
      continue i + 1
    }
    let end = operator_end(source, i)
    if end > i {
      add_span(spans, 0, i, end, Operator)
      let operator = source[i:end]
      can_start_expression = match operator {
        "]" | "++" | "--" => false
        "." | "?." => false
        _ => true
      }
      if operator != "*" || name_kind is None {
        name_kind = None
      }
      control_paren = false
      pending_block = operator is ("=>" | ";")
      continue end
    }
    // Unknown code units never produce a span at a surrogate midpoint.
    continue i + 1
  }
  @highlight.SourceHighlights::from_spans(source, spans)
}

///|
fn is_newline(char : UInt16) -> Bool {
  char is ('\r' | '\n' | '\u2028' | '\u2029')
}

///|
fn is_space(char : UInt16) -> Bool {
  char
  is (' '
  | '\t'
  | '\r'
  | '\n'
  | '\u000b'
  | '\u000c'
  | '\u00a0'
  | '\u2028'
  | '\u2029'
  | '\uFEFF')
}

///|
fn ascii_digit(char : UInt16) -> Bool {
  char is ('0'..='9')
}

///|
fn identifier_start(char : UInt16) -> Bool {
  char is ('a'..='z' | 'A'..='Z' | '_' | '$') ||
  (char >= '\u0080' && !is_space(char))
}

///|
fn identifier_part(char : UInt16) -> Bool {
  identifier_start(char) || ascii_digit(char)
}

///|
fn word_kind(word : StringView) -> HighlightKind {
  match word {
    "break"
    | "case"
    | "catch"
    | "continue"
    | "debugger"
    | "do"
    | "else"
    | "finally"
    | "for"
    | "if"
    | "return"
    | "switch"
    | "throw"
    | "try"
    | "while"
    | "with" => Control
    "async" | "await" | "yield" => Async
    "true" | "false" => Boolean
    "static" | "get" | "set" => Modifier
    "in" | "instanceof" => Operator
    "class"
    | "const"
    | "default"
    | "delete"
    | "export"
    | "extends"
    | "from"
    | "function"
    | "import"
    | "let"
    | "new"
    | "of"
    | "super"
    | "this"
    | "typeof"
    | "var"
    | "void"
    | "null"
    | "undefined" => Keyword
    _ => Variable
  }
}

///|
fn word_allows_expression(word : StringView, kind : HighlightKind) -> Bool {
  if kind is (Variable | Function | Type | Boolean) {
    false
  } else {
    !(word is ("this" | "super" | "null" | "undefined"))
  }
}

///|
fn following_paren(source : String, start : Int) -> Bool {
  let mut i = start
  while i < source.length() {
    if is_space(source[i]) {
      i += 1
    } else if i + 1 < source.length() &&
      source[i] == '/' &&
      source[i + 1] == '*' {
      i += 2
      while i + 1 < source.length() &&
            !(source[i] == '*' && source[i + 1] == '/') {
        i += 1
      }
      i = Int::min(i + 2, source.length())
    } else {
      break
    }
  }
  i < source.length() && source[i] == '('
}

///|
fn escaped_end(source : String, slash : Int) -> Int {
  let mut end = Int::min(slash + 2, source.length())
  if end < source.length() && source[slash + 1] == '\r' && source[end] == '\n' {
    end += 1
  } else if end < source.length() && source.get_char(end) is None {
    // A backslash followed by an astral character still has one character
    // boundary after both UTF-16 code units.
    end += 1
  }
  end
}

///|
fn scan_quote(
  source : String,
  start : Int,
  spans : Array[HighlightSpan],
) -> Int {
  let quote = source[start]
  let mut i = start + 1
  let mut plain = start
  while i < source.length() {
    if source[i] == quote {
      i += 1
      break
    }
    if is_newline(source[i]) {
      break
    }
    if source[i] == '\\' && i + 1 < source.length() {
      let end = escaped_end(source, i)
      add_span(spans, 0, plain, i, StringLiteral)
      add_span(spans, 0, i, end, Escape)
      plain = end
      i = end
    } else {
      i += 1
    }
  }
  add_span(spans, 0, plain, i, StringLiteral)
  i
}

///|
fn scan_template(
  source : String,
  start : Int,
  opening : Bool,
  spans : Array[HighlightSpan],
) -> (Int, TemplateStop) {
  let mut i = if opening { start + 1 } else { start }
  let mut plain = start
  while i < source.length() {
    if source[i] == '`' {
      i += 1
      add_span(spans, 0, plain, i, StringLiteral)
      return (i, Closed)
    }
    if source[i] == '$' && i + 1 < source.length() && source[i + 1] == '{' {
      add_span(spans, 0, plain, i, StringLiteral)
      add_span(spans, 0, i, i + 2, Interpolation)
      return (i + 2, Expression)
    }
    if source[i] == '\\' && i + 1 < source.length() {
      let end = escaped_end(source, i)
      add_span(spans, 0, plain, i, StringLiteral)
      add_span(spans, 0, i, end, Escape)
      plain = end
      i = end
    } else {
      i += 1
    }
  }
  add_span(spans, 0, plain, i, StringLiteral)
  (i, EndOfSource)
}

///|
fn scan_regex(source : String, start : Int) -> Int {
  let mut i = start + 1
  let mut in_class = false
  while i < source.length() && !is_newline(source[i]) {
    if source[i] == '\\' &&
      i + 1 < source.length() &&
      !is_newline(source[i + 1]) {
      i = escaped_end(source, i)
    } else if source[i] == '[' {
      in_class = true
      i += 1
    } else if source[i] == ']' {
      in_class = false
      i += 1
    } else if source[i] == '/' && !in_class {
      i += 1
      while i < source.length() && identifier_part(source[i]) {
        i += 1
      }
      return i
    } else {
      i += 1
    }
  }
  i
}

///|
fn radix_digit(char : UInt16, radix : Int) -> Bool {
  if radix == 2 {
    char is ('0' | '1')
  } else if radix == 8 {
    char is ('0'..='7')
  } else {
    ascii_digit(char) || char is ('a'..='f' | 'A'..='F')
  }
}

///|
fn scan_number(source : String, start : Int) -> Int {
  let size = source.length()
  let mut i = start
  if i + 2 < size &&
    source[i] == '0' &&
    source[i + 1] is ('x' | 'X' | 'b' | 'B' | 'o' | 'O') {
    let radix = match source[i + 1] {
      'b' | 'B' => 2
      'o' | 'O' => 8
      _ => 16
    }
    i += 2
    while i < size && (radix_digit(source[i], radix) || source[i] == '_') {
      i += 1
    }
    if i == start + 2 {
      return start + 1
    }
    if i < size && source[i] == 'n' {
      i += 1
    }
    return i
  }
  if source[i] == '.' {
    i += 1
  }
  while i < size && (ascii_digit(source[i]) || source[i] == '_') {
    i += 1
  }
  if i < size && source[i] == '.' && source[start] != '.' {
    i += 1
    while i < size && (ascii_digit(source[i]) || source[i] == '_') {
      i += 1
    }
  }
  if i < size && source[i] is ('e' | 'E') {
    let exponent = i
    i += 1
    if i < size && source[i] is ('+' | '-') {
      i += 1
    }
    let digits = i
    while i < size && (ascii_digit(source[i]) || source[i] == '_') {
      i += 1
    }
    if i == digits {
      i = exponent
    }
  }
  if i < size &&
    source[i] == 'n' &&
    source[start] != '.' &&
    !(source[start:i].contains(".") ||
    source[start:i].contains("e") ||
    source[start:i].contains("E")) {
    i += 1
  }
  i
}

///|
fn operator_end(source : String, start : Int) -> Int {
  let size = source.length()
  if start + 4 <= size && source[start:start + 4] == ">>>=" {
    return start + 4
  }
  if start + 3 <= size &&
    source[start:start + 3]
    is ("==="
    | "!=="
    | ">>>"
    | "<<="
    | ">>="
    | "**="
    | "&&="
    | "||="
    | "??="
    | "...") {
    return start + 3
  }
  if start + 2 <= size &&
    source[start:start + 2]
    is ("=>"
    | "=="
    | "!="
    | "<="
    | ">="
    | "++"
    | "--"
    | "&&"
    | "||"
    | "??"
    | "**"
    | "?."
    | "+="
    | "-="
    | "*="
    | "/="
    | "%="
    | "&="
    | "|="
    | "^="
    | "<<"
    | ">>") {
    return start + 2
  }
  if source[start]
    is ('+'
    | '-'
    | '*'
    | '/'
    | '%'
    | '='
    | '!'
    | '<'
    | '>'
    | '?'
    | ':'
    | '.'
    | '~'
    | '&'
    | '|'
    | '^'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}'
    | ','
    | ';') {
    start + 1
  } else {
    start
  }
}
