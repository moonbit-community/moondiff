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
  @yaml.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
test "nested block mappings sequences and scalar keys" {
  let source = "services:\n  - name: web\n    enabled: true\n    ports:\n      - 8080\n      - 443\n  - name: worker\nempty:\ntrue: false\n123: null\n? explicit key\n: value"
  assert_eq(colored_line(source), [("services", Variable), (":", Operator)])
  assert_eq(colored_line(source, line=2), [
    ("-", Operator),
    ("name", Variable),
    (":", Operator),
    ("web", StringLiteral),
  ])
  assert_eq(colored_line(source, line=3), [
    ("enabled", Variable),
    (":", Operator),
    ("true", Boolean),
  ])
  assert_eq(colored_line(source, line=5), [("-", Operator), ("8080", Number)])
  assert_eq(colored_line(source, line=9), [
    ("true", Variable),
    (":", Operator),
    ("false", Boolean),
  ])
  assert_eq(colored_line(source, line=10), [
    ("123", Variable),
    (":", Operator),
    ("null", Keyword),
  ])
  assert_eq(colored_line(source, line=11), [
    ("?", Operator),
    ("explicit key", Variable),
  ])
  assert_eq(colored_line(source, line=12), [
    (":", Operator),
    ("value", StringLiteral),
  ])
}

///|
test "nested flow containers and JSON adjacent values" {
  assert_eq(
    colored_line(
      "{\"key\":1, 'flag':false, nested: [true, {value: null}], empty, url: https://host/x#part}",
    ),
    [
      ("{", Operator),
      ("\"key\"", Variable),
      (":", Operator),
      ("1", Number),
      (",", Operator),
      ("'flag'", Variable),
      (":", Operator),
      ("false", Boolean),
      (",", Operator),
      ("nested", Variable),
      (":", Operator),
      ("[", Operator),
      ("true", Boolean),
      (",", Operator),
      ("{", Operator),
      ("value", Variable),
      (":", Operator),
      ("null", Keyword),
      ("}", Operator),
      ("]", Operator),
      (",", Operator),
      ("empty", Variable),
      (",", Operator),
      ("url", Variable),
      (":", Operator),
      ("https://host/x#part", StringLiteral),
      ("}", Operator),
    ],
  )
  assert_eq(colored_line("[plain: 1, \"quoted\":2, :empty, ? query: null]"), [
    ("[", Operator),
    ("plain", Variable),
    (":", Operator),
    ("1", Number),
    (",", Operator),
    ("\"quoted\"", Variable),
    (":", Operator),
    ("2", Number),
    (",", Operator),
    (":empty", StringLiteral),
    (",", Operator),
    ("?", Operator),
    ("query", Variable),
    (":", Operator),
    ("null", Keyword),
    ("]", Operator),
  ])
}

///|
test "comments and colons require YAML separation" {
  for
    value in [
      "https://host:8080/path#part", "abc#def", "12:34:56", ":value", "-value", "?value",
      "a,b[0]{x}", "a 'quoted' \"text\"", "a\u00a0#b",
    ] {
    assert_eq(colored_line("key: \{value} # note"), [
      ("key", Variable),
      (":", Operator),
      (value, StringLiteral),
      ("# note", Comment),
    ])
  }
  assert_eq(colored_line("https://host/path: value"), [
    ("https://host/path", Variable),
    (":", Operator),
    ("value", StringLiteral),
  ])
  assert_eq(colored_line("key:#still-a-key: value"), [
    ("key:#still-a-key", Variable),
    (":", Operator),
    ("value", StringLiteral),
  ])
  assert_eq(colored_line("{key:[1,2], empty:, other:}"), [
    ("{", Operator),
    ("key", Variable),
    (":", Operator),
    ("[", Operator),
    ("1", Number),
    (",", Operator),
    ("2", Number),
    ("]", Operator),
    (",", Operator),
    ("empty", Variable),
    (":", Operator),
    (",", Operator),
    ("other", Variable),
    (":", Operator),
    ("}", Operator),
  ])
}

///|
test "directives documents tags anchors and aliases are lexical" {
  let source = "%YAML 1.2 # version\n%TAG !e! tag:example.com,2026: # handle\n---\ndefault: &中文😀 !!str 123\ncopy: *中文😀\nlocal: !e!thing {value: !<tag:example.com,2026:custom> on}\n... # end\n--- false\n---suffix\n...suffix"
  assert_eq(colored_line(source), [
    ("%YAML 1.2", Control),
    ("# version", Comment),
  ])
  assert_eq(colored_line(source, line=2), [
    ("%TAG !e! tag:example.com,2026:", Control),
    ("# handle", Comment),
  ])
  assert_eq(colored_line(source, line=3), [("---", Control)])
  assert_eq(colored_line(source, line=4), [
    ("default", Variable),
    (":", Operator),
    ("&中文😀", Attribute),
    ("!!str", Type),
    ("123", Number),
  ])
  assert_eq(colored_line(source, line=5), [
    ("copy", Variable),
    (":", Operator),
    ("*中文😀", Attribute),
  ])
  assert_eq(colored_line(source, line=6), [
    ("local", Variable),
    (":", Operator),
    ("!e!thing", Type),
    ("{", Operator),
    ("value", Variable),
    (":", Operator),
    ("!<tag:example.com,2026:custom>", Type),
    ("on", StringLiteral),
    ("}", Operator),
  ])
  assert_eq(colored_line(source, line=7), [("...", Control), ("# end", Comment)])
  assert_eq(colored_line("--- false"), [("---", Control), ("false", Boolean)])
  assert_eq(colored_line("---suffix"), [("---suffix", StringLiteral)])
  assert_eq(colored_line("...suffix"), [("...suffix", StringLiteral)])
  assert_eq(colored_line("\uFEFF---\nkey: ! value"), [("---", Control)])
}
