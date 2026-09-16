///|
test "line budgets retain later flow quoted and block scalar state" {
  let lines = [
    "[" + "0,".repeat(512) + "\"open中😀",
    "# still string\", {key: true}]",
    "\"" + "a\\n".repeat(512) + "\": |2-",
    "  # block content: false 中😀",
    "tail: 42",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    let highlights = @yaml.highlight(source)
    assert_true(highlights.line(1).is_empty())
    assert_true(highlights.line(3).is_empty())
    assert_eq(colored_line(source, line=2), [
      ("# still string\"", StringLiteral),
      (",", Operator),
      ("{", Operator),
      ("key", Variable),
      (":", Operator),
      ("true", Boolean),
      ("}", Operator),
      ("]", Operator),
    ])
    assert_eq(colored_line(source, line=4), [(lines[3], StringLiteral)])
    assert_eq(colored_line(source, line=5), [
      ("tail", Variable),
      (":", Operator),
      ("42", Number),
    ])
    assert_character_boundaries(source)
  }
}

///|
test "source budget skips a crowded line without losing its multiline string" {
  let full = "[" + "0,".repeat(511) + "]\n"
  let near = "[" + "0,".repeat(510) + "0]\n"
  let source = full.repeat(15) + near + "value: \"first\nsecond\"\ntail: true"
  let highlights = @yaml.highlight(source)
  for line in 1..<=15 {
    assert_eq(highlights.line(line).length(), 1024)
  }
  assert_eq(highlights.line(16).length(), 1023)
  assert_true(highlights.line(17).is_empty())
  assert_eq(highlights.line(18).to_owned(), [
    { start: 0, end: 7, kind: StringLiteral, },
  ])
  assert_true(highlights.line(19).is_empty())
  let exhausted = @yaml.highlight(full.repeat(16) + "tail: true")
  assert_eq(exhausted.line(16).length(), 1024)
  assert_true(exhausted.line(17).is_empty())
  assert_character_boundaries(source)
}
