///|
test "all newline spellings preserve spliced source and UTF-16 columns" {
  for newline in ["\n", "\r\n", "\r"] {
    let lines = [
      "#define VALUE \\", "  42", "/* 中文😀", "", " */ int 中 = 1;", "const char *s = \"😀\\",
      "中\\n\";", "\"unfinished", "int next = 3;", "",
    ]
    let source = lines.join(newline)
    let highlights = @c.highlight(source)
    for index, line in lines {
      let mut previous = 0
      for span in highlights.line(index + 1) {
        assert_true(previous <= span.start && span.start < span.end)
        assert_true(span.end <= line.length())
        assert_false(line[span.start:span.end].is_empty())
        previous = span.end
      }
    }
    assert_eq(highlights.line(2).to_owned(), [
      { start: 2, end: 4, kind: Number, },
    ])
    assert_eq(highlights.line(3).to_owned(), [
      { start: 0, end: 7, kind: Comment, },
    ])
    assert_true(highlights.line(4).is_empty())
    assert_eq(highlights.line(5)[1], { start: 4, end: 7, kind: Type, })
    assert_eq(highlights.line(7).to_owned(), [
      { start: 0, end: 1, kind: StringLiteral, },
      { start: 1, end: 3, kind: Escape, },
      { start: 3, end: 4, kind: StringLiteral, },
    ])
    assert_eq(highlights.line(9)[0].kind, Type)
    assert_true(highlights.line(10).is_empty())
  }
}

///|
test "unfinished C tokens keep ordered nonoverlapping character boundaries" {
  let examples = [
    "", "\\", "\\\n", "\\\r\n\\\n", "#", "#define", "#define f(", "#include <unfinished",
    "#include \"unfinished", "/*", "//", "'", "\"", "L'\\", "u8\"😀", "\"\\q\\u1\\x\"",
    "\"\\😀\"", "int f( { x + @ ` 0x1p-;", "0x", "1e+", "0b1'", "[[", "[[vendor::attr((x)",
    "[[deprecated(\"bad\")", "/* ** / \"//\"", "中😀 a\\\n\\\n_t(1);", "u\\\n8\"\\x4\\\n1\"",
  ]
  for source in examples {
    let highlights = @c.highlight(source)
    // Inputs use LF, except the splice-only CRLF case. A retained CR remains
    // within the line's bound, while the shared index excludes terminators.
    for index, line in source.split("\n").to_array() {
      let mut previous = 0
      for span in highlights.line(index + 1) {
        assert_true(previous <= span.start && span.start < span.end)
        assert_true(span.end <= line.length())
        assert_false(line[span.start:span.end].is_empty())
        previous = span.end
      }
    }
  }
  assert_eq(@c.highlight("/* unfinished\\\n\\\n").line(2).to_owned(), [
    { start: 0, end: 1, kind: Comment, },
  ])
}

///|
test "every truncated prefix of mixed C source remains safe to render" {
  let source = "#define CALL(x) \\\r\n run(x)\n[[deprecated(\"中文😀\\n\")]]\nint run(void) { /* note\n */ return 0x1.fp-2; }\n"
  for end in 0..<=source.length() {
    // Only truncate at a UTF-16 character boundary, as editor edits do.
    if end < source.length() && source.get_char(end) is None {
      continue
    }
    let prefix = source[:end].to_owned()
    let highlights = @c.highlight(prefix)
    for index, line in prefix.split("\n").to_array() {
      let mut previous = 0
      for span in highlights.line(index + 1) {
        assert_true(previous <= span.start && span.start < span.end)
        assert_true(span.end <= line.length())
        assert_false(line[span.start:span.end].is_empty())
        previous = span.end
      }
    }
  }
}

///|
fn assert_character_boundaries(source : String) -> Unit raise {
  let highlights = @c.highlight(source)
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .to_array()
  for index, line in lines {
    let mut previous = 0
    for span in highlights.line(index + 1) {
      assert_true(previous <= span.start && span.start < span.end)
      assert_true(span.end <= line.length())
      assert_true(line.get_char(span.start) is Some(_))
      assert_true(
        span.end == line.length() || line.get_char(span.end) is Some(_),
      )
      assert_false(line[span.start:span.end].is_empty())
      previous = span.end
    }
  }
}

///|
test "C lexical fixes preserve physical UTF-16 columns across every newline spelling" {
  let lines = [
    "struct", "%:define BAD <:<:broken( \\", "  nested", "\\u4e2d😀Tag;", "[ /* 中😀 */ <:",
    "vendor::note(<%中😀; %>, <:x:>),", "] /* close */ :> int restored();", "%:define JOIN(\\u4e2d_t) \\u4e2d_t %:%: value",
    "%:include <:header%:%:.h>", "call\\u4\\", "e2d😀();", "tail\\U0001\\", "F600_t value;",
    "<\\", ":<:nodiscard:>\\", ":> int after();", "// <% 中文😀", "",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    let highlights = @c.highlight(source)
    assert_character_boundaries(source)
    assert_eq(highlights.line(3).to_owned(), [
      { start: 2, end: 8, kind: AttributeParameter, },
    ])
    assert_eq(highlights.line(4).to_owned(), [
      { start: 0, end: 11, kind: Type, },
    ])
    assert_eq(highlights.line(10).to_owned(), [
      { start: 0, end: 8, kind: Function, },
    ])
    assert_eq(highlights.line(11).to_owned(), [
      { start: 0, end: 5, kind: Function, },
    ])
    assert_eq(highlights.line(12).to_owned(), [
      { start: 0, end: 11, kind: Type, },
    ])
    assert_eq(highlights.line(13)[0], { start: 0, end: 6, kind: Type, })
    assert_eq(highlights.line(14).to_owned(), [
      { start: 0, end: 2, kind: Attribute, },
    ])
    assert_eq(highlights.line(15).to_owned(), [
      { start: 0, end: 3, kind: Attribute, },
      { start: 3, end: 12, kind: Attribute, },
      { start: 12, end: 15, kind: Attribute, },
    ])
    assert_eq(highlights.line(16)[0], { start: 0, end: 2, kind: Attribute, })
    // Truncate escapes, digraphs, comments and directives at every editor-safe
    // boundary, including between CR and LF and within a spliced token.
    for end in 0..<=source.length() {
      if end < source.length() && source.get_char(end) is None {
        continue
      }
      assert_character_boundaries(source[:end].to_owned())
    }
  }
}
