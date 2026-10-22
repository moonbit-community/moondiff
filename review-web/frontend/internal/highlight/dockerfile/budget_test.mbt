///|
test "crowded lines are dropped after scanning without losing later states" {
  let crowded = "RUN " + "true;".repeat(600) + " \\\n"
  let source = crowded +
    "printf \"$HOME\"\n" +
    ("CMD [" + "\"x\",".repeat(600) + "\"open\\\n") +
    "continued\"]\n" +
    ("COPY " + "--x=y ".repeat(400) + "<<EOF /x\n") +
    "value $NAME\nEOF\nFROM scratch"
  let highlights = @dockerfile.highlight(source)
  assert_true(highlights.line(1).is_empty())
  assert_eq(colored_line(source, line=2), [
    ("printf", Function),
    ("\"", StringLiteral),
    ("$", Interpolation),
    ("HOME", Variable),
    ("\"", StringLiteral),
  ])
  assert_true(highlights.line(3).is_empty())
  assert_eq(colored_line(source, line=4), [
    ("continued\"", StringLiteral),
    ("]", Operator),
  ])
  assert_true(highlights.line(5).is_empty())
  assert_eq(colored_line(source, line=6), [
    ("value ", StringLiteral),
    ("$", Interpolation),
    ("NAME", Variable),
  ])
  assert_eq(colored_line(source, line=7), [("EOF", Control)])
  assert_eq(colored_line(source, line=8), [("FROM", Keyword)])
  assert_character_boundaries(source)
}

///|
test "source budget exhaustion does not affect scanner safety" {
  let full = ("RUN " + "true;".repeat(511) + "x\n").repeat(16)
  let source = full + "RUN <<EOF\necho $HOME\nEOF\nFROM scratch"
  let highlights = @dockerfile.highlight(source)
  assert_eq(highlights.line(16).length(), 1024)
  assert_true(highlights.line(17).is_empty())
  assert_true(highlights.line(18).is_empty())
  assert_true(highlights.line(19).is_empty())
  assert_true(highlights.line(20).is_empty())
  assert_character_boundaries(source)
}
