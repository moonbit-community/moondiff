///|
fn assert_character_boundaries(source : String) -> Unit raise {
  let highlights = @dockerfile.highlight(source)
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
}

///|
test "unfinished tokens and every UTF-16-safe prefix remain renderable" {
  let examples = [
    "", " ", "#", "# syntax=", "# escape=", "RUN", "RUN \\", "RUN '$X", "RUN \"中文😀$NAME\\",
    "RUN echo ${NAME:-", "RUN echo $(printf x", "CMD [", "CMD [\"中文😀\\", "COPY <<",
    "COPY <<'EOF", "RUN <<EOF\n中文😀 $X", "ONBUILD", "ONBUILD RUN", "HEALTHCHECK --interval= CMD",
    "ENV X=${Y",
  ]
  for source in examples {
    assert_character_boundaries(source)
  }
  let mixed = "# syntax=docker/dockerfile:1\r\nFROM 😀 AS base\nRUN printf \"中文😀 $HOME\\n\" && \\\r\n echo ${HOME:-/tmp}\nCOPY <<'EOF' /x\n中文😀 $literal\nEOF\n"
  for end in 0..<=mixed.length() {
    if end < mixed.length() && mixed.get_char(end) is None {
      continue
    }
    assert_character_boundaries(mixed[:end].to_owned())
  }
}

///|
test "LF CRLF and CR preserve the same lexical state" {
  let lines = [
    "# escape=`", "RUN echo 中文😀 `", "# skipped", " && printf \"$HOME\"", "COPY <<EOF /x",
    "hello $NAME", "EOF", "FROM alpine AS final", "",
  ]
  for newline in ["\n", "\r\n", "\r"] {
    let source = lines.join(newline)
    assert_character_boundaries(source)
    assert_eq(colored_line(source, line=2).last(), Some(("`", Escape)))
    assert_eq(colored_line(source, line=3), [("# skipped", Comment)])
    assert_eq(colored_line(source, line=4)[0], ("&&", Operator))
    assert_eq(colored_line(source, line=6), [
      ("hello ", StringLiteral),
      ("$", Interpolation),
      ("NAME", Variable),
    ])
    assert_eq(colored_line(source, line=8), [("FROM", Keyword), ("AS", Control)])
  }
}

///|
test "unterminated JSON strings variables continuations and heredocs stop safely at EOF" {
  for
    source in [
      "CMD [\"open\nFROM fake", "RUN echo ${OPEN\nFROM fake", "RUN echo \\", "COPY <<EOF /x\nno delimiter $NAME",
      "RUN <<EOF\necho $NAME",
    ] {
    assert_character_boundaries(source)
  }
  assert_eq(colored_line("COPY <<EOF /x\nno delimiter $NAME", line=2), [
    ("no delimiter ", StringLiteral),
    ("$", Interpolation),
    ("NAME", Variable),
  ])
}
