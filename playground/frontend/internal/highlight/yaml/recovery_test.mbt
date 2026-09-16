///|
fn assert_character_boundaries(source : String) -> Unit raise {
  let highlights = @yaml.highlight(source)
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
      previous = span.end
    }
  }
  assert_true(highlights.line(0).is_empty())
  assert_true(highlights.line(lines.length() + 1).is_empty())
}

///|
test "empty and incomplete YAML remains safe to render" {
  for
    source in [
      "", " ", "\t", "\r\n", "\uFEFF", "#", "%", "---", "...", "-", "?", ":", "[",
      "{", "[[{", "]", "}", ",", "key:", "&", "*", "!", "!<", "!<tag:unfinished",
      "'", "\"", "'it''", "\"\\", "\"\\x", "\"\\u123", "\"\\😀", "|", "|+", "|-2",
      "key: |\n\n", "key: \"unfinished\n  中文😀", "[123abc, {key: false", "中文😀:#not-comment",
    ] {
    assert_character_boundaries(source)
  }
  assert_true(@yaml.highlight("").line(1).is_empty())
  assert_eq(colored_line("key: \"unfinished\n # still string", line=2), [
    (" # still string", StringLiteral),
  ])
}

///|
test "every truncated prefix preserves UTF-16 boundaries for all newline spellings" {
  let lines = [
    "%YAML 1.2 # 中😀", "---", "中文😀: &源 !<tag:example.com,2026:x> {\"键\\u4e2d\": [123abc, true, *源]}",
    "single: 'it''s", "  # 中文😀'", "double: \"😀\\", "  中\\U0001F600\"",
    "plain: 123", "  false", "block:", "  - key: |2- # header", "      # 中😀: null",
    "    next: 42", "...", "",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    assert_character_boundaries(source)
    assert_eq(@yaml.highlight(source).line(3)[0], {
      start: 0,
      end: 4,
      kind: Variable,
    })
    for end in 0..<=source.length() {
      if end < source.length() && source.get_char(end) is None {
        continue
      }
      assert_character_boundaries(source[:end].to_owned())
    }
  }
}
