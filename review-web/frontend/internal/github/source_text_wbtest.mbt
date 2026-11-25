///|
test "bounded source lines preserve universal newlines and Unicode" {
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
    assert_eq(split_source_lines_bounded(source, max_lines=-1), None)
    assert_eq(split_source_lines_bounded(source, max_lines=0), None)
    assert_eq(
      split_source_lines_bounded(source, max_lines=expected.length() - 1),
      None,
    )
    assert_eq(
      split_source_lines_bounded(source, max_lines=expected.length()),
      Some(expected),
    )
    assert_eq(
      split_source_lines_bounded(source, max_lines=expected.length() + 1),
      Some(expected),
    )
  }
}

///|
test "bounded source lines match regex for short Unicode inputs and limits" {
  fn check(source : String, depth : Int32) -> Unit raise {
    let expected = re"\r\n|\r|\n"
      .split(source)
      .map(StringView::to_owned)
      .collect()
    for max_lines in 0..<(expected.length() + 2) {
      assert_eq(
        split_source_lines_bounded(source, max_lines~),
        if expected.length() <= max_lines {
          Some(expected)
        } else {
          None
        },
      )
    }
    if depth > 0 {
      for token in ["a", "中", "😀", "\r", "\n"] {
        check(source + token, depth - 1)
      }
    }
  }

  check("", 7)
}

///|
test "source validation enforces the 20,000 line boundary for all newlines" {
  for terminator in ["\n", "\r\n", "\r"] {
    let source = ("名😀" + terminator).repeat(MAX_SOURCE_LINES - 1)
    for tail in ["", "last😀"] {
      guard check_source(@utf8.encode(source + tail)) is Renderable(lines) else {
        fail("expected exactly 20,000 lines to render")
      }
      assert_eq(lines.length(), MAX_SOURCE_LINES)
      assert_eq(lines[0], "名😀")
      assert_eq(lines[MAX_SOURCE_LINES - 1], tail)
      assert_true(
        check_source(@utf8.encode(source + tail + terminator))
        is Rejected(_, false),
      )
    }
  }
}
