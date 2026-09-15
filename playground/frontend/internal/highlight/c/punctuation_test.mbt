///|
test "C digraph delimiters preserve ordinary punctuation scopes" {
  assert_eq(colored_line("int data<:2:> = <%1, 2%>; run(data<:0:>);"), [
    ("int", Type),
    ("data", Variable),
    ("2", Number),
    ("=", Operator),
    ("1", Number),
    ("2", Number),
    ("run", Function),
    ("data", Variable),
    ("0", Number),
  ])
  assert_eq(colored_line("%:define JOIN(a, b) %:a %:%: b"), [
    ("%:", Control),
    ("define", Control),
    ("JOIN", Function),
    ("a", Variable),
    ("b", Variable),
    ("%:", Operator),
    ("a", Variable),
    ("%:%:", Operator),
    ("b", Variable),
  ])
  assert_eq(colored_line("%:%: define x %: y ## z"), [
    ("%:%:", Operator),
    ("define", Variable),
    ("x", Variable),
    ("%:", Operator),
    ("y", Variable),
    ("##", Operator),
    ("z", Variable),
  ])
}

///|
test "digraphs in headers strings and comments keep their original spelling" {
  assert_eq(colored_line("/* <: %: */ %:include <dir/<:%:%:.h>"), [
    ("/* <: %: */", Comment),
    ("%:", Control),
    ("include", Control),
    ("<dir/<:%:%:.h>", StringLiteral),
  ])
  assert_eq(colored_line("%:include \"dir/<:%>.h\""), [
    ("%:", Control),
    ("include", Control),
    ("\"dir/<:%>.h\"", StringLiteral),
  ])
  assert_eq(colored_line("\"<: :> <% %> %: %:%:\" /* <% */"), [
    ("\"<: :> <% %> %: %:%:\"", StringLiteral),
    ("/* <% */", Comment),
  ])
}

///|
test "attribute brackets mix digraphs with ordinary spelling and trivia" {
  for (left, right) in [("[", "]"), ("<:", ":>")] {
    for (other_left, other_right) in [("[", "]"), ("<:", ":>")] {
      for gap in ["", " ", " /* bracket */ "] {
        let source = "struct \{left}\{gap}\{other_left}nodiscard\{right}\{gap}\{other_right} Node; restored();"
        let expected : Array[(String, @highlight.HighlightKind)] = [
          ("struct", Keyword),
        ]
        if gap == "" {
          expected.push((left + other_left, Attribute))
        } else {
          expected.push((left, Attribute))
          if gap != " " {
            expected.push(("/* bracket */", Comment))
          }
          expected.push((other_left, Attribute))
        }
        expected.push(("nodiscard", Attribute))
        if gap == "" {
          expected.push((right + other_right, Attribute))
        } else {
          expected.push((right, Attribute))
          if gap != " " {
            expected.push(("/* bracket */", Comment))
          }
          expected.push((other_right, Attribute))
        }
        expected.push(("Node", Type))
        expected.push(("restored", Function))
        assert_eq(colored_line(source), expected)
      }
    }
  }
}

///|
test "digraph attribute arguments count nested brackets and braces" {
  assert_eq(
    colored_line(
      "<:[vendor::attr(<%x; y%>, <:z:>, [<:q:>]), nodiscard]:> int restored();",
    ),
    [
      ("<:[", Attribute),
      ("vendor", Attribute),
      ("::", Operator),
      ("attr", Attribute),
      ("x", AttributeParameter),
      ("y", AttributeParameter),
      ("z", AttributeParameter),
      ("q", AttributeParameter),
      ("nodiscard", Attribute),
      ("]:>", Attribute),
      ("int", Type),
      ("restored", Function),
    ],
  )
  assert_eq(
    colored_line("%:define OPEN <: /* note */\n<:x:>; restored();", line=2),
    [("x", Variable), ("restored", Function)],
  )
  let source = "%:define BAD <:<:attr(\n%:define TAG struct\nrestored();"
  assert_eq(colored_line(source, line=2)[3], ("struct", Keyword))
  assert_eq(colored_line(source, line=3), [("restored", Function)])
}

///|
test "a separated attribute bracket still occupies the start of its line" {
  let source = "<:\n[ %:define note ]\n:> %:include name; restored();"
  assert_eq(colored_line(source, line=2), [
    ("[", Attribute),
    ("%:", Operator),
    ("define", Attribute),
    ("note", Attribute),
    ("]", Attribute),
  ])
  assert_eq(colored_line(source, line=3), [
    (":>", Attribute),
    ("%:", Operator),
    ("include", Variable),
    ("name", Variable),
    ("restored", Function),
  ])
}
