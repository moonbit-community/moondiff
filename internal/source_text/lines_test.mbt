///|
test "universal newline splitting preserves trailing lines" {
  for
    sample in [
      ("", [""]),
      ("a", ["a"]),
      ("a\n", ["a", ""]),
      ("a\r\n", ["a", ""]),
      ("a\r", ["a", ""]),
      ("a\nb\r\nc\rd", ["a", "b", "c", "d"]),
      ("\r\n\n\r", ["", "", "", ""]),
      ("😀\r\n中\na\r", ["😀", "中", "a", ""]),
      ("a\n\rb\r\r\n\n", ["a", "", "b", "", "", ""]),
      ("😀中\u{2028}\u{2029}\t", ["😀中\u{2028}\u{2029}\t"]),
    ] {
    let (source, expected) = sample
    assert_eq(@source_text.split_lines(source), expected)
  }
}

///|
test "universal line ranges exclude complete terminators" {
  assert_eq(@source_text.line_ranges("a\nb\r\nc\rd\r\n"), [
    (0, 1),
    (2, 3),
    (5, 6),
    (7, 8),
    (10, 10),
  ])
  assert_eq(@source_text.line_ranges("😀\r\n中\na\r"), [
    (0, 1),
    (3, 4),
    (5, 6),
    (7, 7),
  ])
}

///|
test "universal newline splitting matches regex for short Unicode inputs" {
  fn check(source : String, depth : Int32) -> Unit raise {
    let expected = re"\r\n|\r|\n"
      .split(source)
      .map(StringView::to_owned)
      .collect()
    assert_eq(@source_text.split_lines(source), expected)
    if depth > 0 {
      for token in ["a", "中", "😀", "\r", "\n"] {
        check(source + token, depth - 1)
      }
    }
  }

  // All 97,656 inputs of zero to seven tokens, including adjacent CR/LF.
  check("", 7)
}
