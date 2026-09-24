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
  @json.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
test "JSON keys values escapes numbers and punctuation" {
  assert_eq(
    colored_line(
      "{\"title\":\"中文😀\\n\",\"count\":-12.5e+2,\"ok\":true,\"empty\":null,\"items\":[false,0]}",
    ),
    [
      ("{", Operator),
      ("\"title\"", Variable),
      (":", Operator),
      ("\"中文😀", StringLiteral),
      ("\\n", Escape),
      ("\"", StringLiteral),
      (",", Operator),
      ("\"count\"", Variable),
      (":", Operator),
      ("-12.5e+2", Number),
      (",", Operator),
      ("\"ok\"", Variable),
      (":", Operator),
      ("true", Boolean),
      (",", Operator),
      ("\"empty\"", Variable),
      (":", Operator),
      ("null", Keyword),
      (",", Operator),
      ("\"items\"", Variable),
      (":", Operator),
      ("[", Operator),
      ("false", Boolean),
      (",", Operator),
      ("0", Number),
      ("]", Operator),
      ("}", Operator),
    ],
  )
  assert_eq(colored_line("{\"a\\u4e2d\":\"\\/\\\"\\\\\"}"), [
    ("{", Operator),
    ("\"a", Variable),
    ("\\u4e2d", Escape),
    ("\"", Variable),
    (":", Operator),
    ("\"", StringLiteral),
    ("\\/", Escape),
    ("\\\"", Escape),
    ("\\\\", Escape),
    ("\"", StringLiteral),
    ("}", Operator),
  ])
}

///|
test "strict JSON does not color comments or invalid atoms" {
  assert_eq(colored_line("[01,truefalse,+1,0x10,NaN,]"), [
    ("[", Operator),
    (",", Operator),
    (",", Operator),
    (",", Operator),
    (",", Operator),
    (",", Operator),
    ("]", Operator),
  ])
  let source = "{\"ok\":true, // false\\n\"next\":null}".replace_all(
    old="\\n",
    new="\n",
  )
  assert_eq(colored_line(source), [
    ("{", Operator),
    ("\"ok\"", Variable),
    (":", Operator),
    ("true", Boolean),
    (",", Operator),
  ])
  assert_eq(colored_line(source, line=2), [
    ("\"next\"", Variable),
    (":", Operator),
    ("null", Keyword),
    ("}", Operator),
  ])
}

///|
fn assert_boundaries(source : String) -> Unit raise {
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .to_array()
  let highlights = @json.highlight(source)
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
test "JSON preserves UTF-16 boundaries and recovers at all newline spellings" {
  for newline in ["\n", "\r\n", "\r"] {
    let source = ["{\"😀\":\"中\\n\",", "\"unfinished", "\"next\":-2.3E-4}"].join(
      newline,
    )
    assert_boundaries(source)
    assert_eq(colored_line(source, line=2), [("\"unfinished", Variable)])
    assert_eq(colored_line(source, line=3), [
      ("\"next\"", Variable),
      (":", Operator),
      ("-2.3E-4", Number),
      ("}", Operator),
    ])
  }
  let source = "{\"😀\":\"\\u4e2d\",\"x\":[true,null,-12.5e+2]}"
  for end in 0..<=source.length() {
    if end < source.length() && source.get_char(end) is None {
      continue
    }
    assert_boundaries(source[:end].to_owned())
  }
}

///|
test "JSON dropped lines do not prevent later highlights" {
  let source = "[" + "0,".repeat(512) + "\ntrue]"
  let highlights = @json.highlight(source)
  assert_true(highlights.line(1).is_empty())
  assert_eq(colored_line(source, line=2), [("true", Boolean), ("]", Operator)])
  assert_boundaries(source)
  let exhausted = @json.highlight(("0,".repeat(512) + "\n").repeat(16) + "true")
  assert_eq(exhausted.line(16).length(), 1024)
  assert_true(exhausted.line(17).is_empty())
}
