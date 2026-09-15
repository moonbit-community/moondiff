///|
fn colored_line(
  source : String,
  line? : Int = 1,
) -> Array[(String, HighlightKind)] {
  let text = source.split("\n").to_array()[line - 1].to_owned()
  SourceHighlights::from_source(source)
  .line(line)
  .to_owned()
  .map(span => (slice(text, span.start, span.end), span.kind))
}

///|
test "MoonBit declarations, calls, types, packages, and control flow" {
  assert_eq(
    colored_line(
      "pub async fn Box::run(x : Int) -> Bool { if true { @io.print(x); x.map!(f) } else { false } }",
    ),
    [
      ("pub", Modifier),
      ("async", Async),
      ("fn", Keyword),
      ("Box", Type),
      ("run", Function),
      ("x", Variable),
      ("Int", Type),
      ("->", Keyword),
      ("Bool", Type),
      ("if", Control),
      ("true", Boolean),
      ("@io", Package),
      ("print", Function),
      ("x", Variable),
      ("x", Variable),
      ("map", Function),
      ("f", Variable),
      ("else", Control),
      ("false", Boolean),
    ],
  )
  assert_eq(
    colored_line("fn[T] identity(x : T) { x }; let value = identity(42)"),
    [
      ("fn", Keyword),
      ("T", Type),
      ("identity", Function),
      ("x", Variable),
      ("T", Type),
      ("x", Variable),
      ("let", Keyword),
      ("value", Variable),
      ("=", Operator),
      ("identity", Function),
      ("42", Number),
    ],
  )
  assert_eq(colored_line("fn unfinished"), [
    ("fn", Keyword),
    ("unfinished", Function),
  ])
  assert_eq(
    colored_line("item.field + tuple.0 - 0xffUL * 1.5 / 2 != 0 && not false"),
    [
      ("item", Variable),
      ("+", Operator),
      ("tuple", Variable),
      ("0", Number),
      ("-", Operator),
      ("0xffUL", Number),
      ("*", Operator),
      ("1.5", Number),
      ("/", Operator),
      ("2", Number),
      ("!=", Operator),
      ("0", Number),
      ("&&", Operator),
      ("not", Operator),
      ("false", Boolean),
    ],
  )
}

///|
test "attributes have directive names, parameters, and string escapes" {
  assert_eq(
    colored_line(
      (
        #|#deprecated("use \"new\"", since="0.1", enabled=true)
      ),
    ),
    [
      ("#deprecated", Attribute),
      ("\"use ", StringLiteral),
      ("\\\"", Escape),
      ("new", StringLiteral),
      ("\\\"", Escape),
      ("\"", StringLiteral),
      ("since", AttributeParameter),
      ("=", Operator),
      ("\"0.1\"", StringLiteral),
      ("enabled", AttributeParameter),
      ("=", Operator),
      ("true", AttributeParameter),
    ],
  )
  assert_eq(colored_line("#cfg.target(js, native)"), [
    ("#cfg.target", Attribute),
    ("js", AttributeParameter),
    ("native", AttributeParameter),
  ])
}

///|
test "string and byte literals distinguish valid escapes from raw text" {
  assert_eq(
    colored_line(
      (
        #|"😀\n\t\r\b\0\\\"\'\x41\o123\u4e2d\u{1F600}\q" b'\x41' b"<&>"
      ),
    ),
    [
      ("\"😀", StringLiteral),
      ("\\n", Escape),
      ("\\t", Escape),
      ("\\r", Escape),
      ("\\b", Escape),
      ("\\0", Escape),
      ("\\\\", Escape),
      ("\\\"", Escape),
      ("\\'", Escape),
      ("\\x41", Escape),
      ("\\o123", Escape),
      ("\\u4e2d", Escape),
      ("\\u{1F600}", Escape),
      ("\\q\"", StringLiteral),
      ("b'", StringLiteral),
      ("\\x41", Escape),
      ("'", StringLiteral),
      ("b\"<&>\"", StringLiteral),
    ],
  )
}

///|
test "nested interpolations use original offsets with braces and quoted atoms" {
  assert_eq(
    colored_line(
      (
        #|"中文😀 \{ if true { "inner \{f(42)}" } else { "}" } }!"
      ),
    ),
    [
      ("\"中文😀 ", StringLiteral),
      ("\\{", Interpolation),
      ("if", Control),
      ("true", Boolean),
      ("\"inner ", StringLiteral),
      ("\\{", Interpolation),
      ("f", Function),
      ("42", Number),
      ("}", Interpolation),
      ("\"", StringLiteral),
      ("else", Control),
      ("\"}\"", StringLiteral),
      ("}", Interpolation),
      ("!\"", StringLiteral),
    ],
  )
}

///|
test "raw and interpolated multiline strings preserve markers and indentation" {
  let source = "let text =\n  #|中文😀 \\n \\{raw}\n  $|<&> \\n \\{call(3)}\nlet next = 4"
  assert_eq(colored_line(source, line=2), [
    ("#|", Operator),
    ("中文😀 \\n \\{raw}", StringLiteral),
  ])
  assert_eq(colored_line(source, line=3), [
    ("$|", Operator),
    ("<&> ", StringLiteral),
    ("\\n", Escape),
    (" ", StringLiteral),
    ("\\{", Interpolation),
    ("call", Function),
    ("3", Number),
    ("}", Interpolation),
  ])
  assert_eq(colored_line(source, line=4), [
    ("let", Keyword),
    ("next", Variable),
    ("=", Operator),
    ("4", Number),
  ])
}

///|
test "MoonBit doc fences embed complete code without coloring prose as code" {
  let source =
    #|/// Some docs with `let x = 0`
    #|/// ```mbt test
    #|/// async fn
    #|/// example() -> Int {
    #|///   let text = "😀\{read()}"
    #|///   42 // example
    #|/// }
    #|/// ```
    #|/// More docs
    #|fn actual() {}
  assert_eq(colored_line(source), [("/// Some docs with `let x = 0`", Comment)])
  assert_eq(colored_line(source, line=2), [("/// ```mbt test", Comment)])
  assert_eq(colored_line(source, line=3), [
    ("///", Comment),
    ("async", Async),
    ("fn", Keyword),
  ])
  assert_eq(colored_line(source, line=4), [
    ("///", Comment),
    ("example", Function),
    ("->", Keyword),
    ("Int", Type),
  ])
  assert_eq(colored_line(source, line=5), [
    ("///", Comment),
    ("let", Keyword),
    ("text", Variable),
    ("=", Operator),
    ("\"😀", StringLiteral),
    ("\\{", Interpolation),
    ("read", Function),
    ("}", Interpolation),
    ("\"", StringLiteral),
  ])
  assert_eq(colored_line(source, line=6), [
    ("///", Comment),
    ("42", Number),
    ("// example", Comment),
  ])
  assert_eq(colored_line(source, line=8), [("/// ```", Comment)])
  assert_eq(colored_line(source, line=9), [("/// More docs", Comment)])
}

///|
test "doc fences support tildes, empty languages, and unterminated blocks" {
  for language in ["moonbit test(async)", "MBT", ""] {
    let source = "/// ~~~~\{language}\n/// let x = true\n/// ~~~~"
    assert_eq(colored_line(source, line=2), [
      ("///", Comment),
      ("let", Keyword),
      ("x", Variable),
      ("=", Operator),
      ("true", Boolean),
    ])
  }
  let other = "/// ```js\n/// let x = true\n/// ```\n/// let prose = false"
  assert_eq(colored_line(other, line=2), [("/// let x = true", Comment)])
  assert_eq(colored_line(other, line=4), [("/// let prose = false", Comment)])
  let unfinished = "/// ```mbt\n/// let x = 1\nfn outside() {}\n/// let prose = 2"
  assert_eq(colored_line(unfinished, line=2), [
    ("///", Comment),
    ("let", Keyword),
    ("x", Variable),
    ("=", Operator),
    ("1", Number),
  ])
  assert_eq(colored_line(unfinished, line=4), [("/// let prose = 2", Comment)])
}

///|
test "UTF-16 ranges retain Chinese, emoji, tabs, CRLF, and blank lines" {
  let source = "\tlet x = \"中文😀<&>\"; let y = 12\r\n\r\n// 中文😀\rlet z = 3"
  let highlights = SourceHighlights::from_source(source)
  let number = highlights.line(1).to_owned().filter(span => span.kind is Number)
  assert_eq(number, [{ start: 28, end: 30, kind: Number, }])
  assert_eq(slice(source, 28, 30), "12")
  assert_eq(highlights.line(2).length(), 0)
  assert_eq(highlights.line(3).to_owned(), [
    { start: 0, end: 7, kind: Comment, },
  ])
  assert_eq(
    highlights.line(4).to_owned().last(),
    Some({ start: 8, end: 9, kind: Number, }),
  )
  assert_eq(highlights.line(0).length(), 0)
  assert_eq(highlights.line(99).length(), 0)
  assert_eq(SourceHighlights::from_source("").line(1).length(), 0)
}

///|
test "lexical errors keep valid tokens and never create overlapping or empty ranges" {
  for
    source in [
      "let x = ` 1\nlet y = 2", "fn broken( {", "let s = \"unfinished😀", "\"hello \\{fn x() { 1 }",
      "😀\nlet x = 2", "\"\\{ }\"", "let x = 1\nlet y = 2\n",
    ] {
    let highlights = SourceHighlights::from_source(source)
    for index, line in source.split("\n").to_array() {
      let mut previous = 0
      for span in highlights.line(index + 1) {
        assert_true(span.start >= previous)
        assert_true(span.start < span.end && span.end <= line.length())
        // This also checks that no range splits a surrogate pair.
        assert_false(line[span.start:span.end].is_empty())
        previous = span.end
      }
    }
  }
  assert_eq(colored_line("let x = ` 1"), [
    ("let", Keyword),
    ("x", Variable),
    ("=", Operator),
    ("1", Number),
  ])
}

///|
test "file eligibility follows each rename side and only the mbt extension" {
  for
    (old_path, new_path, old_enabled, new_enabled) in [
      ("before.mbt", "after.txt", true, false),
      ("before.txt", "after.mbt", false, true),
      ("before.mbt", "after.mbt", true, true),
      ("before.mbti", "after.md", false, false),
    ] {
    let file = FileHighlights::new(old_path, new_path, "let x = 1", "let x = 2")
    assert_eq(file.old is Some(_), old_enabled)
    assert_eq(file.new is Some(_), new_enabled)
  }
}

///|
test "Unicode interpolation whitespace and incomplete method names keep their scopes" {
  assert_eq(colored_line("\"\\{\u3000call(1)\u00A0\uFEFF}\""), [
    ("\"", StringLiteral),
    ("\\{", Interpolation),
    ("call", Function),
    ("1", Number),
    ("}", Interpolation),
    ("\"", StringLiteral),
  ])
  assert_eq(colored_line("fn Box::unfinished"), [
    ("fn", Keyword),
    ("Box", Type),
    ("unfinished", Function),
  ])
  assert_eq(colored_line("#cfg(type=Int, async, 1.0)"), [
    ("#cfg", Attribute),
    ("type", AttributeParameter),
    ("=", Operator),
    ("Int", AttributeParameter),
    ("async", AttributeParameter),
    ("1.0", AttributeParameter),
  ])
}

///|
test "doc fences accept tab-separated info and stop at a physical blank line" {
  let source = "/// ```mbt\ttest\r\n/// let x = 1\r\n\r\n/// let prose = 2"
  assert_eq(colored_line(source, line=2), [
    ("///", Comment),
    ("let", Keyword),
    ("x", Variable),
    ("=", Operator),
    ("1", Number),
  ])
  assert_eq(colored_line(source, line=4), [("/// let prose = 2", Comment)])
}
