///|
test "line fallback preserves comments strings and continuations around it" {
  let crowded = "0,".repeat(1024)
  let lines = [
    "/* before 中文😀",
    "close */ " + crowded + "/* 开始😀",
    "正文😀 */ int visible = 1;",
    crowded + "\"open😀\\",
    "续中文😀\\n\"; int after = 2;",
    crowded + "// hidden \\",
    "\"quoted\" int fake();",
    "int tail = 3;",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    let highlights = @c.highlight(source)
    let tokens = line => {
      highlights
      .line(line)
      .to_owned()
      .map(span => (lines[line - 1][span.start:span.end].to_owned(), span.kind))
    }
    assert_eq(tokens(1), [(lines[0], Comment)])
    for line in [2, 4, 6] {
      assert_true(highlights.line(line).is_empty())
    }
    assert_eq(tokens(3), [
      ("正文😀 */", Comment),
      ("int", Type),
      ("visible", Variable),
      ("=", Operator),
      ("1", Number),
    ])
    assert_eq(tokens(5), [
      ("续中文😀", StringLiteral),
      ("\\n", Escape),
      ("\"", StringLiteral),
      ("int", Type),
      ("after", Variable),
      ("=", Operator),
      ("2", Number),
    ])
    assert_eq(tokens(7), [(lines[6], Comment)])
    assert_eq(tokens(8), [
      ("int", Type),
      ("tail", Variable),
      ("=", Operator),
      ("3", Number),
    ])
    assert_character_boundaries(source)
  }
}

///|
test "a comment opened on a line over the remaining budget continues on a later line" {
  let source = ("0,".repeat(1024) + "\n").repeat(15) +
    "0,".repeat(1023) +
    "\nint skipped; /* 中文😀\nint hidden; */\nint tail;"
  let highlights = @c.highlight(source)
  assert_eq(highlights.line(16).length(), 1023)
  assert_true(highlights.line(17).is_empty())
  assert_eq(highlights.line(18).to_owned(), [
    { start: 0, end: 14, kind: Comment, },
  ])
  assert_true(highlights.line(19).is_empty())
}
