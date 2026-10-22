///|
test "literal prefixes and identifiers select the longest token" {
  assert_eq(
    colored_line(
      "u8 u U L u8name u8\"text\" u'中' U'😀' L\"wide\" u8L\"tail\" .5 . ... 1e+ 0x1p-",
    ),
    [
      ("u8", Variable),
      ("u", Variable),
      ("U", Variable),
      ("L", Variable),
      ("u8name", Variable),
      ("u8\"text\"", StringLiteral),
      ("u'中'", StringLiteral),
      ("U'😀'", StringLiteral),
      ("L\"wide\"", StringLiteral),
      ("u8L", Variable),
      ("\"tail\"", StringLiteral),
      (".5", Number),
      (".", Operator),
      ("...", Operator),
      ("1e+", Number),
      ("0x1p-", Number),
    ],
  )
}

///|
test "C whitespace precedes tolerant Unicode identifiers" {
  assert_eq(colored_line("\uFEFF\uFEFFint\u000bname\u000c=\t1;\uFEFFcall();"), [
    ("int", Type),
    ("name", Variable),
    ("=", Operator),
    ("1", Number),
    ("call", Function),
  ])
  for word in ["a\uFEFFb", "\u0080id", "中\u2028😀"] {
    assert_eq(colored_line(word), [(word, Variable)])
    assert_eq(colored_line("\{word}_t"), [(word + "_t", Type)])
    assert_character_boundaries(word)
  }
}

///|
test "block comments stop at the first terminator and recover at EOF" {
  for body in ["", " ", "*", "**", "***", "/**", "中文😀"] {
    let comment = "/*" + body + "*/"
    assert_eq(colored_line("\{comment}call()/**/tail();"), [
      (comment, Comment),
      ("call", Function),
      ("/**/", Comment),
      ("tail", Function),
    ])
  }
  for comment in ["/*", "/**", "/***", "/* /", "/* ** /", "/* /*"] {
    assert_eq(colored_line(comment), [(comment, Comment)])
  }
  assert_eq(colored_line("/* first\n**second */call();/**/tail();", line=2), [
    ("**second */", Comment),
    ("call", Function),
    ("/**/", Comment),
    ("tail", Function),
  ])
}

///|
test "digit separators separate following signs from preprocessing numbers" {
  for number in ["1'e", "0x1'e", "0x1'E", "0x1'p", "0x1'P"] {
    for operator in ["+", "-"] {
      assert_eq(colored_line("\{number}\{operator}2"), [
        (number, Number),
        (operator, Operator),
        ("2", Number),
      ])
    }
  }
  for
    number in [
      "1e+2", "2E-3", "0x1.fp+2", "0X1.FP-2", "1'2e+3", "0x1'fp-2", "1'\\u4e2d",
      "2'\\U0001F600e+3",
    ] {
    assert_eq(colored_line(number), [(number, Number)])
  }
  assert_eq(colored_line("2'\\U00000045-3 1e++2"), [
    ("2'\\U00000045", Number),
    ("-", Operator),
    ("3", Number),
    ("1e+", Number),
    ("+", Operator),
    ("2", Number),
  ])
}

///|
test "separator and exponent branches survive line splicing" {
  for newline in ["\n", "\r\n", "\r"] {
    for
      (prefix, suffix, joined) in [
        ("0x1'", "e+2", true),
        ("0x1'e", "+2", false),
        ("0x1'", "E-2", true),
        ("0x1'P", "-2", false),
      ] {
      let source = prefix + "\\" + newline + suffix
      let highlights = @c.highlight(source)
      assert_eq(highlights.line(1).to_owned(), [
        {
          start: 0,
          end: if joined {
            prefix.length() + 1
          } else {
            prefix.length()
          },
          kind: Number,
        },
      ])
      assert_eq(
        highlights
        .line(2)
        .to_owned()
        .map(span => (suffix[span.start:span.end].to_owned(), span.kind)),
        if joined {
          [
            (suffix[:1].to_owned(), Number),
            (suffix[1:2].to_owned(), Operator),
            ("2", Number),
          ]
        } else {
          [(suffix[:1].to_owned(), Operator), ("2", Number)]
        },
      )
      assert_character_boundaries(source)
    }
    for prefix in ["1e", "0x1.fp", "0x1'fp"] {
      let highlights = @c.highlight(prefix + "\\" + newline + "+2")
      assert_eq(highlights.line(1).to_owned(), [
        { start: 0, end: prefix.length() + 1, kind: Number, },
      ])
      assert_eq(highlights.line(2).to_owned(), [
        { start: 0, end: 2, kind: Number, },
      ])
    }
  }
}
