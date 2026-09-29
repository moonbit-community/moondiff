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
  @dockerfile.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
test "instructions flags stages variables and values" {
  assert_eq(colored_line("FROM --platform=$BUILDPLATFORM alpine AS build"), [
    ("FROM", Keyword),
    ("--platform", Attribute),
    ("=", Operator),
    ("$", Interpolation),
    ("BUILDPLATFORM", Variable),
    ("AS", Control),
  ])
  assert_eq(colored_line("ENV NAME=demo ENABLED=true COUNT=42"), [
    ("ENV", Keyword),
    ("NAME", Variable),
    ("=", Operator),
    ("ENABLED", Variable),
    ("=", Operator),
    ("true", Boolean),
    ("COUNT", Variable),
    ("=", Operator),
    ("42", Number),
  ])
  assert_eq(colored_line("ONBUILD COPY --from=build /src /dst"), [
    ("ONBUILD", Control),
    ("COPY", Keyword),
    ("--from", Attribute),
    ("=", Operator),
    ("build", AttributeParameter),
  ])
}

///|
test "shell and JSON forms" {
  assert_eq(
    colored_line("RUN echo \"$HOME\" && if true; then printf '%s' ok; fi"),
    [
      ("RUN", Keyword),
      ("echo", Function),
      ("\"", StringLiteral),
      ("$", Interpolation),
      ("HOME", Variable),
      ("\"", StringLiteral),
      ("&&", Operator),
      ("if", Control),
      ("true", Boolean),
      (";", Operator),
      ("then", Control),
      ("printf", Function),
      ("'%s'", StringLiteral),
      (";", Operator),
      ("fi", Control),
    ],
  )
  assert_eq(colored_line("ENTRYPOINT [\"sh\", \"-c\", \"echo\\nhello\"]"), [
    ("ENTRYPOINT", Keyword),
    ("[", Operator),
    ("\"sh\"", StringLiteral),
    (",", Operator),
    ("\"-c\"", StringLiteral),
    (",", Operator),
    ("\"echo", StringLiteral),
    ("\\n", Escape),
    ("hello\"", StringLiteral),
    ("]", Operator),
  ])
}

///|
test "parser directives continuations comments and heredocs" {
  let source = "# syntax=docker/dockerfile:1\n# escape=`\nRUN echo one `\n# removed\n  && echo $TWO\nCOPY <<'EOF' /x\n$literal\nEOF\nRUN <<-SH\n\techo $HOME\n\tSH"
  assert_eq(colored_line(source), [
    ("#", Control),
    ("syntax", Attribute),
    ("=", Operator),
    ("docker/dockerfile:1", StringLiteral),
  ])
  assert_eq(colored_line(source, line=2), [
    ("#", Control),
    ("escape", Attribute),
    ("=", Operator),
    ("`", Escape),
  ])
  assert_eq(colored_line(source, line=3), [
    ("RUN", Keyword),
    ("echo", Function),
    ("`", Escape),
  ])
  assert_eq(colored_line(source, line=4), [("# removed", Comment)])
  assert_eq(colored_line(source, line=5), [
    ("&&", Operator),
    ("echo", Function),
    ("$", Interpolation),
    ("TWO", Variable),
  ])
  assert_eq(colored_line(source, line=6), [
    ("COPY", Keyword),
    ("<<", Operator),
    ("'EOF'", StringLiteral),
  ])
  assert_eq(colored_line(source, line=7), [("$literal", StringLiteral)])
  assert_eq(colored_line(source, line=8), [("EOF", Control)])
  assert_eq(colored_line(source, line=10), [
    ("echo", Function),
    ("$", Interpolation),
    ("HOME", Variable),
  ])
  assert_eq(colored_line(source, line=11), [("SH", Control)])
}
