///|
fn colored_line(
  source : String,
  line? : Int = 1,
) -> Array[(String, @highlight.HighlightKind)] {
  let text = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .to_array()[line - 1]
  @javascript.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
test "JavaScript declarations calls classes numbers and operators" {
  assert_eq(colored_line("const count = 0x2fn; let ratio = .5e+2;"), [
    ("const", Keyword),
    ("count", Variable),
    ("=", Operator),
    ("0x2fn", Number),
    (";", Operator),
    ("let", Keyword),
    ("ratio", Variable),
    ("=", Operator),
    (".5e+2", Number),
    (";", Operator),
  ])
  assert_eq(colored_line("function greet(name) { return greet(name); }"), [
    ("function", Keyword),
    ("greet", Function),
    ("(", Operator),
    ("name", Variable),
    (")", Operator),
    ("{", Operator),
    ("return", Control),
    ("greet", Function),
    ("(", Operator),
    ("name", Variable),
    (")", Operator),
    (";", Operator),
    ("}", Operator),
  ])
  assert_eq(colored_line("class Box extends Base { run(x) { return x; } }"), [
    ("class", Keyword),
    ("Box", Type),
    ("extends", Keyword),
    ("Base", Type),
    ("{", Operator),
    ("run", Function),
    ("(", Operator),
    ("x", Variable),
    (")", Operator),
    ("{", Operator),
    ("return", Control),
    ("x", Variable),
    (";", Operator),
    ("}", Operator),
    ("}", Operator),
  ])
  assert_eq(
    colored_line("async function go() { await work(); return true ?? false; }"),
    [
      ("async", Async),
      ("function", Keyword),
      ("go", Function),
      ("(", Operator),
      (")", Operator),
      ("{", Operator),
      ("await", Async),
      ("work", Function),
      ("(", Operator),
      (")", Operator),
      (";", Operator),
      ("return", Control),
      ("true", Boolean),
      ("??", Operator),
      ("false", Boolean),
      (";", Operator),
      ("}", Operator),
    ],
  )
}

///|
test "regex literals are distinct from division after expressions and control parentheses" {
  assert_eq(colored_line("const ratio = left / right / 2;"), [
    ("const", Keyword),
    ("ratio", Variable),
    ("=", Operator),
    ("left", Variable),
    ("/", Operator),
    ("right", Variable),
    ("/", Operator),
    ("2", Number),
    (";", Operator),
  ])
  assert_eq(colored_line("return /a[b/]c\\/d/gi.test(text);"), [
    ("return", Control),
    ("/a[b/]c\\/d/gi", StringLiteral),
    (".", Operator),
    ("test", Function),
    ("(", Operator),
    ("text", Variable),
    (")", Operator),
    (";", Operator),
  ])
  assert_eq(colored_line("if (ready) /x+/.test(text);"), [
    ("if", Control),
    ("(", Operator),
    ("ready", Variable),
    (")", Operator),
    ("/x+/", StringLiteral),
    (".", Operator),
    ("test", Function),
    ("(", Operator),
    ("text", Variable),
    (")", Operator),
    (";", Operator),
  ])
  assert_true(
    colored_line("function f() {} /after/.test(value);").contains(
      ("/after/", StringLiteral),
    ),
  )
  assert_true(colored_line("const object = {} / 2;").contains(("/", Operator)))
}

///|
test "unfinished JavaScript literals retain earlier tokens and recover" {
  assert_eq(colored_line("return /unfinished\nconst after = 2;"), [
    ("return", Control),
    ("/unfinished", StringLiteral),
  ])
  assert_eq(
    colored_line("return /unfinished\nconst after = 2;", line=2)[0],
    ("const", Keyword),
  )
  assert_eq(
    colored_line("const text = `unfinished").last(),
    Some(("`unfinished", StringLiteral)),
  )
  assert_eq(colored_line("/* unfinished\nconst hidden = 2;", line=2), [
    ("const hidden = 2;", Comment),
  ])
}

///|
test "template strings retain nested interpolation and escapes" {
  assert_eq(
    colored_line("const text = `Hi ${name} and ${`[${value + 1}]`}!`;"),
    [
      ("const", Keyword),
      ("text", Variable),
      ("=", Operator),
      ("`Hi ", StringLiteral),
      ("${", Interpolation),
      ("name", Variable),
      ("}", Interpolation),
      (" and ", StringLiteral),
      ("${", Interpolation),
      ("`[", StringLiteral),
      ("${", Interpolation),
      ("value", Variable),
      ("+", Operator),
      ("1", Number),
      ("}", Interpolation),
      ("]`", StringLiteral),
      ("}", Interpolation),
      ("!`", StringLiteral),
      (";", Operator),
    ],
  )
  assert_eq(colored_line("`中文😀\\n${{value: 1}.value}`"), [
    ("`中文😀", StringLiteral),
    ("\\n", Escape),
    ("${", Interpolation),
    ("{", Operator),
    ("value", Variable),
    (":", Operator),
    ("1", Number),
    ("}", Operator),
    (".", Operator),
    ("value", Variable),
    ("}", Interpolation),
    ("`", StringLiteral),
  ])
}

///|
fn assert_boundaries(source : String) -> Unit raise {
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .to_array()
  let highlights = @javascript.highlight(source)
  for index, line in lines {
    let mut previous = 0
    for span in highlights.line(index + 1) {
      assert_true(previous <= span.start && span.start < span.end)
      assert_true(span.end <= line.length())
      assert_true(line.get_char(span.start) is Some(_))
      assert_true(
        span.end == line.length() || line.get_char(span.end) is Some(_),
      )
      previous = span.end
    }
  }
}

///|
test "comments strings and templates recover through all newline spellings" {
  for newline in ["\n", "\r\n", "\r"] {
    let source = [
      "/* 中文😀", " still comment */ const a = 'bad", "const b = 2; // note",
      "const text = `first", "${b + 1} last`;",
    ].join(newline)
    assert_boundaries(source)
    assert_eq(colored_line(source, line=2)[0], (" still comment */", Comment))
    assert_eq(colored_line(source, line=2)[4], ("'bad", StringLiteral))
    assert_eq(colored_line(source, line=3)[0], ("const", Keyword))
    assert_eq(colored_line(source, line=3).last(), Some(("// note", Comment)))
    assert_eq(
      colored_line(source, line=4).last(),
      Some(("`first", StringLiteral)),
    )
    assert_eq(colored_line(source, line=5)[0], ("${", Interpolation))
    assert_eq(colored_line(source, line=5).last(), Some((";", Operator)))
  }
  let source = "const s = `😀${`nested ${name}`}`; // 中文😀"
  for end in 0..<=source.length() {
    if end < source.length() && source.get_char(end) is None {
      continue
    }
    assert_boundaries(source[:end].to_owned())
  }
}

///|
test "JavaScript dropped lines retain multiline state and source budget" {
  let source = "0,".repeat(1024) + "/* open\nstill comment */ const after = 1;"
  let highlights = @javascript.highlight(source)
  assert_true(highlights.line(1).is_empty())
  assert_eq(colored_line(source, line=2)[0], ("still comment */", Comment))
  assert_eq(colored_line(source, line=2)[1], ("const", Keyword))
  assert_boundaries(source)
  let exhausted = @javascript.highlight(
    ("0,".repeat(512) + "\n").repeat(16) + "const tail = 1;",
  )
  assert_eq(exhausted.line(16).length(), 1024)
  assert_true(exhausted.line(17).is_empty())
}
