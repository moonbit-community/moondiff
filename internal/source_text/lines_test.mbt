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
}

///|
test "bounded universal splitting accepts its boundary and stops above it" {
  assert_eq(@source_text.split_lines_bounded("", max_lines=1), Some([""]))
  assert_eq(@source_text.split_lines_bounded("", max_lines=0), None)
  assert_eq(
    @source_text.split_lines_bounded("a\nb\r\nc\rd", max_lines=4),
    Some(["a", "b", "c", "d"]),
  )
  assert_eq(@source_text.split_lines_bounded("a\nb\r\nc\rd", max_lines=3), None)
  assert_eq(
    @source_text.split_lines_bounded("a\r", max_lines=2),
    Some(["a", ""]),
  )
}
