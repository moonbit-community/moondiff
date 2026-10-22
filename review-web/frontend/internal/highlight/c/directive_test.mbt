///|
test "directive attributes and tags do not leak into following code" {
  for body in ["[[deprecated", "[[vendor::attr((", "struct", "enum", "union"] {
    assert_eq(colored_line("#define BROKEN \{body}\nrestored();", line=2), [
      ("restored", Function),
    ])
  }
  let source = "#define FIRST [[broken(\n#define SECOND struct\nrestored();"
  assert_eq(colored_line(source, line=2), [
    ("#", Control),
    ("define", Control),
    ("SECOND", Function),
    ("struct", Keyword),
  ])
  assert_eq(colored_line(source, line=3), [("restored", Function)])
}

///|
test "directives preserve surrounding tags and multiline attribute arguments" {
  let tag = "struct\n#define ATTR [[broken(\n#define TAG union\nNode;"
  assert_eq(colored_line(tag, line=4), [("Node", Type)])
  let source = "struct [[vendor::attr((first,\n#define BROKEN [[missing(\nsecond)),\n#define TAG struct\nnodiscard]] Node;\nrestored();"
  assert_eq(colored_line(source, line=2), [
    ("#", Control),
    ("define", Control),
    ("BROKEN", Function),
    ("[[", Attribute),
    ("missing", Attribute),
  ])
  assert_eq(colored_line(source, line=3), [("second", AttributeParameter)])
  assert_eq(colored_line(source, line=4), [
    ("#", Control),
    ("define", Control),
    ("TAG", Function),
    ("struct", Keyword),
  ])
  assert_eq(colored_line(source, line=5), [
    ("nodiscard", Attribute),
    ("]]", Attribute),
    ("Node", Type),
  ])
  assert_eq(colored_line(source, line=6), [("restored", Function)])
}

///|
test "directive lookahead stops at its logical newline" {
  for comment in ["", " /* note */", " // note"] {
    let source = "#define VALUE value\{comment}\n()"
    assert_eq(colored_line(source)[3], ("value", Variable))
    let open = "#define OPEN [\{comment}\n[x]; restored();"
    assert_eq(colored_line(open, line=2), [
      ("x", Variable),
      ("restored", Function),
    ])
    let close = "#define CLOSE [[note]\{comment}\n] restored();"
    assert_eq(colored_line(close, line=2), [("restored", Function)])
  }
  // Ordinary code can still pair attribute brackets and look ahead across lines.
  let source = "struct [\n[nodiscard] // note\n] Node; call\n();"
  assert_eq(colored_line(source), [("struct", Keyword), ("[", Attribute)])
  assert_eq(colored_line(source, line=3), [
    ("]", Attribute),
    ("Node", Type),
    ("call", Function),
  ])
}

///|
test "directive splices and multiline block comments retain their local state" {
  let source = "#define ATTR [[ \\\n note(\nrestored();\n#define TAG struct \\\nMacroTag\nagain();"
  assert_eq(colored_line(source, line=2), [("note", Attribute)])
  assert_eq(colored_line(source, line=3), [("restored", Function)])
  assert_eq(colored_line(source, line=5), [("MacroTag", Type)])
  assert_eq(colored_line(source, line=6), [("again", Function)])
  let source = "#define ATTR [ /* first\nsecond */ [note\nrestored();"
  assert_eq(colored_line(source, line=2), [
    ("second */", Comment),
    ("[", Attribute),
    ("note", Attribute),
  ])
  assert_eq(colored_line(source, line=3), [("restored", Function)])
  assert_eq(
    colored_line("#define VALUE call /* first\nsecond */ ()")[3],
    ("call", Function),
  )
}
