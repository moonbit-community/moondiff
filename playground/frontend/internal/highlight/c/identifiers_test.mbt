///|
test "complete Unicode escapes stay within identifiers in every position" {
  for
    word in [
      "\\u4e2d", "pre\\u4e2dpost", "tail\\u4e2d", "\\U0001F600", "pre\\U0001F600post",
      "tail\\U0001F600", "\\u4e2d\\U0001F600", "中\\u4e2d😀",
    ] {
    assert_eq(colored_line(word), [(word, Variable)])
    assert_eq(colored_line("\{word} /* call */ ();"), [
      (word, Function),
      ("/* call */", Comment),
    ])
    assert_eq(colored_line("struct \{word};"), [
      ("struct", Keyword),
      (word, Type),
    ])
    assert_eq(colored_line("\{word}_t value;"), [
      (word + "_t", Type),
      ("value", Variable),
    ])
    assert_eq(colored_line("#define \{word}(\{word}_t) \{word}_t"), [
      ("#", Control),
      ("define", Control),
      (word, Function),
      (word + "_t", Variable),
      (word + "_t", Type),
    ])
  }
}

///|
test "preprocessing numbers consume complete Unicode identifier units" {
  for
    number in ["1\\u4e2d", "0x1\\U0001F600suffix", "1'\\u4e2d", "2\\u4e2d3e+4"] {
    assert_eq(colored_line(number), [(number, Number)])
  }
  // A hex digit inside an escape is not an exponent marker in the source.
  assert_eq(colored_line("1\\u00ae+2"), [
    ("1\\u00ae", Number),
    ("+", Operator),
    ("2", Number),
  ])
}

///|
test "malformed Unicode identifiers recover before quotes newlines and code" {
  for word in ["u", "u12", "u12z4", "U0001", "U0001g600"] {
    assert_eq(colored_line("\\\{word} \"text\"; restored();"), [
      (word, Variable),
      ("\"text\"", StringLiteral),
      ("restored", Function),
    ])
    let source = "prefix\\\{word}\nrestored();"
    assert_eq(colored_line(source), [("prefix", Variable), (word, Variable)])
    assert_eq(colored_line(source, line=2), [("restored", Function)])
  }
  assert_eq(colored_line("\\u12\"text\";"), [
    ("u12", Variable),
    ("\"text\"", StringLiteral),
  ])
  assert_eq(colored_line("\\U0001'x';"), [
    ("U0001", Variable),
    ("'x'", StringLiteral),
  ])
}
