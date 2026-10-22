///|
test "YAML 1.2 Core classifies only complete scalar spellings" {
  for
    (values, kind) in [
      ("null Null NULL ~", @highlight.Keyword),
      ("true True TRUE false False FALSE", Boolean),
      (
        "0 -0 +0 0123 -42 +42 0o7 0o077 0xFf 0. -0.0 .5 +.5 1.2 1e2 1E-2 +12e03 -2E+05 .inf .Inf .INF +.inf -.Inf .nan .NaN .NAN",
        Number,
      ),
      (
        "yes Yes YES no No NO on On ON off Off OFF y n Trueish tRuE nUlL 123abc 1_000 0b10 0o8 0x 0XFF +0xFF -0o7 1e+ 1.2.3 +.nan .Nan .iNF 2026-09-16 12:34:56",
        StringLiteral,
      ),
    ] {
    for value in values.split(" ") {
      assert_eq(colored_line(value.to_owned()), [(value.to_owned(), kind)])
      assert_eq(
        colored_line("key: \{value}  # note")[2],
        (value.to_owned(), kind),
      )
    }
  }
  assert_eq(colored_line("123 abc"), [("123 abc", StringLiteral)])
  assert_eq(colored_line("[123abc, yes, 123]"), [
    ("[", Operator),
    ("123abc", StringLiteral),
    (",", Operator),
    ("yes", StringLiteral),
    (",", Operator),
    ("123", Number),
    ("]", Operator),
  ])
}

///|
test "quoted scalars override implicit types and color keys and escapes" {
  for
    value in [
      "'true'", "\"123\"", "'null'", "\"yes\"", "''", "\"\"", "'# : [ ]'",
    ] {
    assert_eq(colored_line(value), [(value, StringLiteral)])
    assert_eq(colored_line("\{value}: false"), [
      (value, Variable),
      (":", Operator),
      ("false", Boolean),
    ])
  }
  assert_eq(colored_line("'it''s': 'don''t \\n'"), [
    ("'it", Variable),
    ("''", Escape),
    ("s'", Variable),
    (":", Operator),
    ("'don", StringLiteral),
    ("''", Escape),
    ("t \\n'", StringLiteral),
  ])
  assert_eq(colored_line("\"key\\n\": \"value\""), [
    ("\"key", Variable),
    ("\\n", Escape),
    ("\"", Variable),
    (":", Operator),
    ("\"value\"", StringLiteral),
  ])
  for
    escape in [
      "\\0", "\\a", "\\b", "\\t", "\\n", "\\v", "\\f", "\\r", "\\e", "\\ ", "\\\t",
      "\\\"", "\\/", "\\\\", "\\N", "\\_", "\\L", "\\P", "\\xFF", "\\u4e2d", "\\U0001F600",
    ] {
    assert_eq(colored_line("\"中😀\{escape}\""), [
      ("\"中😀", StringLiteral),
      (escape, Escape),
      ("\"", StringLiteral),
    ])
  }
  for escape in ["\\q", "\\xF", "\\u123", "\\U0001", "\\😀"] {
    assert_eq(colored_line("\"\{escape}\""), [("\"\{escape}\"", StringLiteral)])
  }
}
