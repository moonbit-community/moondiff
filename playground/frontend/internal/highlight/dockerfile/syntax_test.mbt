///|
test "all standard instructions are case insensitive" {
  for
    word in "ADD ARG CMD COPY ENTRYPOINT ENV EXPOSE FROM HEALTHCHECK LABEL MAINTAINER RUN SHELL STOPSIGNAL USER VOLUME WORKDIR".split(
      " ",
    ) {
    for spelling in [word, word.to_lower(), word.to_owned()] {
      assert_eq(
        colored_line("\{spelling} value")[0],
        (spelling.to_owned(), Keyword),
      )
    }
  }
  for spelling in ["ONBUILD", "onbuild", "OnBuIlD"] {
    assert_eq(colored_line("\{spelling} RUN echo ok")[0], (spelling, Control))
  }
}

///|
test "parser directive scope values and invalid late directives" {
  let source = "#check=skip=JSONArgsRecommended,StageNameCasing;error=true\r\n# SYNTAX = docker/dockerfile:1\r\nFROM alpine\r\n# escape=`\r\nRUN echo one && \\\r\necho two"
  assert_eq(colored_line(source), [
    ("#", Control),
    ("check", Attribute),
    ("=", Operator),
    ("skip", Attribute),
    ("=", Operator),
    ("JSONArgsRecommended", AttributeParameter),
    (",", Operator),
    ("StageNameCasing", AttributeParameter),
    (";", Operator),
    ("error", Attribute),
    ("=", Operator),
    ("true", Boolean),
  ])
  assert_eq(colored_line(source, line=2)[1], ("SYNTAX", Attribute))
  assert_eq(colored_line(source, line=4), [("# escape=`", Comment)])
  assert_eq(colored_line(source, line=5).last(), Some(("\\", Escape)))
  assert_eq(colored_line(source, line=6)[0], ("echo", Function))

  let duplicate = "# escape=`\n# escape=\\\nRUN echo first && `\necho second"
  assert_eq(colored_line(duplicate, line=2), [("# escape=\\", Comment)])
  // The first valid directive remains effective; the duplicate doesn't switch it.
  assert_eq(colored_line(duplicate, line=3).last(), Some(("`", Escape)))
  assert_eq(colored_line(duplicate, line=4)[0], ("echo", Function))
}

///|
test "builder fields JSON values and nested instructions" {
  assert_eq(colored_line("ARG VERSION=3"), [
    ("ARG", Keyword),
    ("VERSION", Variable),
    ("=", Operator),
    ("3", Number),
  ])
  assert_eq(colored_line("LABEL org.example.enabled=true count=12"), [
    ("LABEL", Keyword),
    ("org.example.enabled", Variable),
    ("=", Operator),
    ("true", Boolean),
    ("count", Variable),
    ("=", Operator),
    ("12", Number),
  ])
  assert_eq(colored_line("HEALTHCHECK --interval=5s CMD curl -f / || exit 1"), [
    ("HEALTHCHECK", Keyword),
    ("--interval", Attribute),
    ("=", Operator),
    ("5s", AttributeParameter),
    ("CMD", Control),
    ("curl", Function),
    ("-f", Attribute),
    ("||", Operator),
    ("exit", Function),
    ("1", Number),
  ])
  assert_eq(colored_line("HEALTHCHECK NONE"), [
    ("HEALTHCHECK", Keyword),
    ("NONE", Control),
  ])
  assert_eq(colored_line("RUN --mount=from=$STAGE,type=bind echo ok"), [
    ("RUN", Keyword),
    ("--mount", Attribute),
    ("=", Operator),
    ("from=", AttributeParameter),
    ("$", Interpolation),
    ("STAGE", Variable),
    (",", Operator),
    ("type=bind", AttributeParameter),
    ("echo", Function),
  ])
  assert_eq(colored_line("SHELL [\"powershell\", \"-command\"]"), [
    ("SHELL", Keyword),
    ("[", Operator),
    ("\"powershell\"", StringLiteral),
    (",", Operator),
    ("\"-command\"", StringLiteral),
    ("]", Operator),
  ])
}

///|
test "variables command substitutions escapes and operators" {
  assert_eq(
    colored_line(
      "RUN NAME=world printf \"%s\" ${NAME:-fallback} $(echo ok) >out",
    ),
    [
      ("RUN", Keyword),
      ("NAME", Variable),
      ("=", Operator),
      ("printf", Function),
      ("\"%s\"", StringLiteral),
      ("${", Interpolation),
      ("NAME", Variable),
      (":-", Operator),
      ("}", Interpolation),
      ("$(", Interpolation),
      ("echo", Function),
      (")", Interpolation),
      (">", Operator),
    ],
  )
  assert_eq(colored_line("WORKDIR /opt/$USER/${APP+default}"), [
    ("WORKDIR", Keyword),
    ("$", Interpolation),
    ("USER", Variable),
    ("${", Interpolation),
    ("APP", Variable),
    ("+", Operator),
    ("}", Interpolation),
  ])
}

///|
test "multiple RUN and COPY heredocs are consumed in declaration order" {
  let source = "RUN <<A cat && <<-'B'\necho $ONE\nA\n\techo $TWO\n\tB\nCOPY <<X <<'Y' /dst\nhello $NAME\nX\nliteral $NAME\nY\nFROM scratch"
  assert_eq(colored_line(source), [
    ("RUN", Keyword),
    ("<<", Operator),
    ("A", StringLiteral),
    ("cat", Function),
    ("&&", Operator),
    ("<<-", Operator),
    ("'B'", StringLiteral),
  ])
  assert_eq(colored_line(source, line=2), [
    ("echo", Function),
    ("$", Interpolation),
    ("ONE", Variable),
  ])
  assert_eq(colored_line(source, line=3), [("A", Control)])
  assert_eq(colored_line(source, line=4), [("echo", Function)])
  assert_eq(colored_line(source, line=5), [("B", Control)])
  assert_eq(colored_line(source, line=7), [
    ("hello ", StringLiteral),
    ("$", Interpolation),
    ("NAME", Variable),
  ])
  assert_eq(colored_line(source, line=9), [("literal $NAME", StringLiteral)])
  assert_eq(colored_line(source, line=11), [("FROM", Keyword)])
}
