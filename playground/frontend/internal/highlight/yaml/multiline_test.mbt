///|
test "quoted strings span physical lines without interpreting YAML syntax" {
  for newline in ["\n", "\r\n", "\r"] {
    let source = [
      "double: \"中😀\\", "  # : [ true", "  text\\n\" # comment", "single: 'first",
      "  # : [ false ''quoted''", "  last'", "tail: true",
    ].join(newline)
    assert_eq(colored_line(source), [
      ("double", Variable),
      (":", Operator),
      ("\"中😀", StringLiteral),
      ("\\", Escape),
    ])
    assert_eq(colored_line(source, line=2), [("  # : [ true", StringLiteral)])
    assert_eq(colored_line(source, line=3), [
      ("  text", StringLiteral),
      ("\\n", Escape),
      ("\"", StringLiteral),
      ("# comment", Comment),
    ])
    assert_eq(colored_line(source, line=5), [
      ("  # : [ false ", StringLiteral),
      ("''", Escape),
      ("quoted", StringLiteral),
      ("''", Escape),
    ])
    assert_eq(colored_line(source, line=6), [("  last'", StringLiteral)])
    assert_eq(colored_line(source, line=7), [
      ("tail", Variable),
      (":", Operator),
      ("true", Boolean),
    ])
  }
}

///|
test "plain continuations use the owning block indentation and whole scalar kind" {
  let lines = [
    "inline: 123", "  false", "  null # stop", "nested:", "  123", "  true", "sequence:",
    "  - 123", "    false", "  -", "    123", "    true", "  - key: 123", "      false",
    "    next: 42", "tail: null",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    assert_eq(colored_line(source)[2], ("123", StringLiteral))
    assert_eq(colored_line(source, line=2), [("  false", StringLiteral)])
    assert_eq(colored_line(source, line=3), [
      ("  null", StringLiteral),
      ("# stop", Comment),
    ])
    assert_eq(colored_line(source, line=5), [("123", StringLiteral)])
    assert_eq(colored_line(source, line=6), [("  true", StringLiteral)])
    assert_eq(colored_line(source, line=8), [
      ("-", Operator),
      ("123", StringLiteral),
    ])
    assert_eq(colored_line(source, line=9), [("    false", StringLiteral)])
    assert_eq(colored_line(source, line=11), [("123", StringLiteral)])
    assert_eq(colored_line(source, line=12), [("    true", StringLiteral)])
    assert_eq(colored_line(source, line=13)[3], ("123", StringLiteral))
    assert_eq(colored_line(source, line=14), [("      false", StringLiteral)])
    assert_eq(colored_line(source, line=15), [
      ("next", Variable),
      (":", Operator),
      ("42", Number),
    ])
    assert_eq(colored_line(source, line=16), [
      ("tail", Variable),
      (":", Operator),
      ("null", Keyword),
    ])
  }
  let source = "key: first\n\n  - text\n  \"quoted\"\n  &anchor !tag # end\nnext: true"
  assert_eq(colored_line(source, line=3), [("  - text", StringLiteral)])
  assert_eq(colored_line(source, line=4), [("  \"quoted\"", StringLiteral)])
  assert_eq(colored_line(source, line=5), [
    ("  &anchor !tag", StringLiteral),
    ("# end", Comment),
  ])
  assert_eq(colored_line("123\n  # stop\nother: 1"), [("123", Number)])
}

///|
test "flow mappings retain their own key state across lines and nested containers" {
  let source = "config: {\n  first: [\n    true,\n    {nested: false}\n  ],\n  \"second\":123,\n  third: [123\n    false, null],\n  last: true\n}\ntail: 42"
  assert_eq(colored_line(source, line=3), [("true", Boolean), (",", Operator)])
  assert_eq(colored_line(source, line=4), [
    ("{", Operator),
    ("nested", Variable),
    (":", Operator),
    ("false", Boolean),
    ("}", Operator),
  ])
  assert_eq(colored_line(source, line=6), [
    ("\"second\"", Variable),
    (":", Operator),
    ("123", Number),
    (",", Operator),
  ])
  assert_eq(colored_line(source, line=7), [
    ("third", Variable),
    (":", Operator),
    ("[", Operator),
    ("123", StringLiteral),
  ])
  assert_eq(colored_line(source, line=8), [
    ("    false", StringLiteral),
    (",", Operator),
    ("null", Keyword),
    ("]", Operator),
    (",", Operator),
  ])
  assert_eq(colored_line(source, line=9), [
    ("last", Variable),
    (":", Operator),
    ("true", Boolean),
  ])
  assert_eq(colored_line(source, line=11), [
    ("tail", Variable),
    (":", Operator),
    ("42", Number),
  ])
}

///|
test "literal folded and chomping headers preserve indented text" {
  for
    header in [
      "|", ">", "|-", "|+", ">-", ">+", "|2", "|2-", "|-2", ">2+", ">+2",
    ] {
    let source = "key: \{header} # header\n\n  # content: true &anchor \\n\n    nested: false\n  ---\nnext: 42"
    assert_eq(colored_line(source), [
      ("key", Variable),
      (":", Operator),
      (header, Operator),
      ("# header", Comment),
    ])
    assert_eq(colored_line(source, line=3), [
      ("  # content: true &anchor \\n", StringLiteral),
    ])
    assert_eq(colored_line(source, line=4), [
      ("    nested: false", StringLiteral),
    ])
    assert_eq(colored_line(source, line=5), [("  ---", StringLiteral)])
    assert_eq(colored_line(source, line=6), [
      ("next", Variable),
      (":", Operator),
      ("42", Number),
    ])
  }
  for scalar in ["|word", ">word", "|0", "|22", "|+-", "| foo"] {
    assert_eq(colored_line(scalar), [(scalar, StringLiteral)])
  }
}

///|
test "block indentation follows compact mappings sequences and properties" {
  let lines = [
    "root:", "  - key: |2-", "      text", "    next: true", "  - >1", "   text",
    "  -", "    |2", "    text", "tagged: &anchor !custom >+2", "  text", "tail: null",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    assert_eq(colored_line(source, line=2), [
      ("-", Operator),
      ("key", Variable),
      (":", Operator),
      ("|2-", Operator),
    ])
    for line in [3, 6, 9, 11] {
      assert_eq(colored_line(source, line~), [(lines[line - 1], StringLiteral)])
    }
    assert_eq(colored_line(source, line=4), [
      ("next", Variable),
      (":", Operator),
      ("true", Boolean),
    ])
    assert_eq(colored_line(source, line=12), [
      ("tail", Variable),
      (":", Operator),
      ("null", Keyword),
    ])
  }
  let source = "key: |\n\n    content\n   # outside\nnext: true"
  assert_eq(colored_line(source, line=3), [("    content", StringLiteral)])
  assert_eq(colored_line(source, line=4), [("# outside", Comment)])
  assert_eq(colored_line("|1\n text\n...", line=2), [(" text", StringLiteral)])
  assert_eq(colored_line("--- >\n text\n...", line=3), [("...", Control)])
}

///|
test "explicit scalar keys and document boundaries reset structural state" {
  let source = "? 'first\n  second'\n: 1\n?\n  plain\n  key\n: 2\n---\ntrue\n...\n--- [\n--- false"
  assert_eq(colored_line(source), [("?", Operator), ("'first", Variable)])
  assert_eq(colored_line(source, line=2), [("  second'", Variable)])
  assert_eq(colored_line(source, line=5), [("plain", Variable)])
  assert_eq(colored_line(source, line=6), [("  key", Variable)])
  assert_eq(colored_line(source, line=9), [("true", Boolean)])
  assert_eq(colored_line(source, line=12), [
    ("---", Control),
    ("false", Boolean),
  ])
}

///|
test "collection keys retain block indentation and block scalar keys have key scopes" {
  let source = "- [name, {nested: true}]: |2\n    body\n  next: true\n? |2\n  literal key\n: 1\n? >\n  folded\n  key\n: 2"
  assert_eq(colored_line(source, line=2), [("    body", StringLiteral)])
  assert_eq(colored_line(source, line=3), [
    ("next", Variable),
    (":", Operator),
    ("true", Boolean),
  ])
  assert_eq(colored_line(source, line=5), [("  literal key", Variable)])
  assert_eq(colored_line(source, line=6), [(":", Operator), ("1", Number)])
  assert_eq(colored_line(source, line=8), [("  folded", Variable)])
  assert_eq(colored_line(source, line=9), [("  key", Variable)])
  assert_eq(colored_line(source, line=10), [(":", Operator), ("2", Number)])
  assert_character_boundaries(source)
}

///|
test "alias and property-only keys retain compact block indentation" {
  for newline in ["\n", "\r\n", "\r"] {
    for key in ["*a", "!!str", "&a", "!!str &a", "&a !!str"] {
      for sequence in ["  - ", "  - - "] {
        let indent = " ".repeat(sequence.length())
        let body = "\{indent}  body 中😀"
        let source = [
          "root:",
          "\{sequence}\{key} : |2",
          body,
          "\{indent}sibling: true",
          "tail: null",
        ].join(newline)
        assert_eq(colored_line(source, line=3), [(body, StringLiteral)])
        assert_eq(colored_line(source, line=4), [
          ("sibling", Variable),
          (":", Operator),
          ("true", Boolean),
        ])
        assert_eq(colored_line(source, line=5), [
          ("tail", Variable),
          (":", Operator),
          ("null", Keyword),
        ])
        assert_character_boundaries(source)
      }
    }
  }
}

///|
test "multiline quoted flow keys retain adjacent value separators" {
  for newline in ["\n", "\r\n", "\r"] {
    for quote in ["\"", "'"] {
      for (open, close) in [("{", "}"), ("[", "]")] {
        for gap in ["", " \t"] {
          let following = if open == "{" {
            "next: false"
          } else {
            "false, null"
          }
          let source = [
            "\{open}? \{quote}a",
            " b中😀\{quote}\{gap}:1,",
            " \{following}\{close}",
            "tail: true",
          ].join(newline)
          assert_eq(colored_line(source), [
            (open, Operator),
            ("?", Operator),
            ("\{quote}a", Variable),
          ])
          assert_eq(colored_line(source, line=2), [
            (" b中😀\{quote}", Variable),
            (":", Operator),
            ("1", Number),
            (",", Operator),
          ])
          assert_eq(
            colored_line(source, line=3),
            if open == "{" {
              [
                ("next", Variable),
                (":", Operator),
                ("false", Boolean),
                (close, Operator),
              ]
            } else {
              [
                ("false", Boolean),
                (",", Operator),
                ("null", Keyword),
                (close, Operator),
              ]
            },
          )
          assert_eq(colored_line(source, line=4), [
            ("tail", Variable),
            (":", Operator),
            ("true", Boolean),
          ])
          assert_character_boundaries(source)
        }
      }
    }
  }
}

///|
test "flow colon adjacency expires after newlines and intervening tokens" {
  for newline in ["\n", "\r\n", "\r"] {
    for
      node in ["\"a\{newline} b中😀\"", "'a\{newline} b中😀'", "[]", "{}"] {
      let source = "[\{node}\{newline} :1, false]"
      let line = if node == "[]" || node == "{}" { 2 } else { 3 }
      assert_eq(colored_line(source, line~), [
        (":1", StringLiteral),
        (",", Operator),
        ("false", Boolean),
        ("]", Operator),
      ])
      assert_character_boundaries(source)
      let source = "[\{node}, :1, false]"
      let spans = colored_line(source, line=line - 1)
      assert_eq(spans[spans.length() - 4:], [
        (":1", StringLiteral),
        (",", Operator),
        ("false", Boolean),
        ("]", Operator),
      ])
      assert_character_boundaries(source)
    }
  }
}
