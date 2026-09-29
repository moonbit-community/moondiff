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
  @markdown.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
fn has_token(
  source : String,
  token : String,
  kind : @highlight.HighlightKind,
  line? : Int = 1,
) -> Bool {
  colored_line(source, line~).any(item => item == (token, kind))
}

///|
fn assert_boundaries(source : String) -> Unit raise {
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .to_array()
  let highlights = @markdown.highlight(source)
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
test "GFM block markers headings tasks definitions and tables" {
  let source = [
    "> # **Title**", "- [x] done", "Term", "====", "[ref]: https://example.com",
    "| Name | Value |", "| :--- | ----: |", "| a | b |", "---",
  ].join("\n")
  assert_true(has_token(source, ">", Control))
  assert_true(has_token(source, "#", Control))
  assert_true(has_token(source, "Title", Modifier))
  assert_true(has_token(source, "[x]", Boolean, line=2))
  assert_true(has_token(source, "Term", Keyword, line=3))
  assert_true(has_token(source, "====", Control, line=4))
  assert_true(has_token(source, "ref", Function, line=5))
  assert_true(has_token(source, "https://example.com", StringLiteral, line=5))
  assert_true(has_token(source, "|", Operator, line=6))
  assert_true(has_token(source, "| :--- | ----: |", Operator, line=7))
  assert_true(has_token(source, "---", Control, line=9))
  let dash_heading = "Heading\n---"
  assert_true(has_token(dash_heading, "Heading", Keyword))
  assert_true(has_token(dash_heading, "---", Control, line=2))
}

///|
test "GFM inline constructs use stable lexical categories" {
  let source = "*em* **strong** ~~gone~~ `x * y` [link](https://e.test) ![alt][id] <b class=\"x\"> <https://auto.test> me@example.test &amp; \\* www.example.com  "
  assert_true(has_token(source, "em", Modifier))
  assert_true(has_token(source, "strong", Modifier))
  assert_true(has_token(source, "gone", Modifier))
  assert_true(has_token(source, "x * y", StringLiteral))
  assert_true(has_token(source, "link", Function))
  assert_true(has_token(source, "https://e.test", StringLiteral))
  assert_true(has_token(source, "alt", Function))
  assert_true(has_token(source, "id", StringLiteral))
  assert_true(has_token(source, "<b", Type))
  assert_true(has_token(source, "class", Attribute))
  assert_true(has_token(source, "https://auto.test", StringLiteral))
  assert_true(has_token(source, "me@example.test", StringLiteral))
  assert_true(has_token(source, "&amp;", Escape))
  assert_true(has_token(source, "\\*", Escape))
  assert_true(has_token(source, "www.example.com", StringLiteral))
  assert_true(has_token(source, "  ", Escape))
}

///|
test "fenced aliases embed existing highlighters and preserve container columns" {
  let cases = [
    ("moonbit", "let x = 1", @highlight.Keyword),
    ("mbt", "let x = 1", Keyword),
    ("c", "int x = 1;", Type),
    ("h", "int x = 1;", Type),
    ("yaml", "key: true", Variable),
    ("yml", "key: true", Variable),
    ("json", "true", Boolean),
    ("javascript", "const x = 1;", Keyword),
    ("js", "const x = 1;", Keyword),
    ("mjs", "const x = 1;", Keyword),
    ("cjs", "const x = 1;", Keyword),
    ("dockerfile", "FROM scratch", Keyword),
    ("containerfile", "FROM scratch", Keyword),
  ]
  for (name, code, kind) in cases {
    for spelling in [name, name.to_upper()] {
      let source = "> - ```\{spelling}\n>   \{code}\n>   ```"
      let tokens = colored_line(source, line=2)
      assert_true(tokens.any(item => item.1 == kind))
      assert_boundaries(source)
    }
  }
  for info in ["", "unknown"] {
    let source = "```\{info}\nplain *code*\n```"
    assert_eq(colored_line(source, line=2), [("plain *code*", StringLiteral)])
  }
}

///|
test "fences code spans and HTML comments recover safely" {
  let open_fence = "```json\ntrue\n# not a heading"
  assert_true(has_token(open_fence, "true", Boolean, line=2))
  assert_true(!has_token(open_fence, "#", Control, line=3))
  assert_true(has_token("`open *em*", "em", Modifier))
  let comment = "before\n<!-- open\n# hidden\nstill"
  assert_true(has_token(comment, "<!-- open", Comment, line=2))
  assert_true(has_token(comment, "# hidden", Comment, line=3))
  assert_true(has_token(comment, "still", Comment, line=4))
  let multiline = "before ``code\ncontinues`` after\n\n<div>\n# raw html\n</div>\n\n    indented *code*"
  assert_true(has_token(multiline, "code", StringLiteral, line=1))
  assert_true(has_token(multiline, "continues", StringLiteral, line=2))
  assert_true(!has_token(multiline, "#", Control, line=5))
  assert_true(has_token(multiline, "indented *code*", StringLiteral, line=8))
  // A different-sized backtick run is not a closing delimiter.
  assert_true(has_token("``one ` two``", "one ` two", StringLiteral))
  let raw_then_markdown = "<script>\nconst raw = '*';\n</script>\n# restored"
  assert_true(!has_token(raw_then_markdown, "*", Operator, line=2))
  assert_true(has_token(raw_then_markdown, "#", Control, line=4))
}

///|
test "UTF-16 truncation and all newline spellings retain valid ordered spans" {
  for newline in ["\n", "\r\n", "\r"] {
    let source = [
      "# 中文😀 *标题*", "> `代码😀`", "[链接](https://例.example)",
    ].join(newline)
    assert_boundaries(source)
    for end in 0..<=source.length() {
      if end == source.length() || source.get_char(end) is Some(_) {
        assert_boundaries(source[0:end].to_owned())
      }
    }
  }
}

///|
test "rendering budgets drop crowded lines and preserve later small lines" {
  let crowded = "[x](u) ".repeat(300)
  let source = crowded + "\n# after"
  let highlights = @markdown.highlight(source)
  assert_true(highlights.line(1).is_empty())
  assert_true(highlights.line(2).length() > 0)
  let exact = "*x* ".repeat(341) + "\\*"
  let full = (exact + "\n").repeat(16) + "# exhausted"
  let exhausted = @markdown.highlight(full)
  assert_true(exhausted.line(16).length() > 0)
  assert_true(exhausted.line(17).is_empty())
}
