///|
test "source spans split all line endings and retain empty physical lines" {
  let source = "/*中😀\r\n\r\n注释\r结束*/\nint"
  let end = source.length() - 3
  let spans : Array[@highlight.HighlightSpan] = [
    { start: end, end: source.length(), kind: Type, },
    { start: 0, end, kind: Comment, },
  ]
  let highlights = @highlight.SourceHighlights::from_spans(source, spans)
  assert_eq(spans[0].start, end)
  for
    (line, length, kind) in [
      (1, 5, @highlight.Comment),
      (2, 0, Comment),
      (3, 2, Comment),
      (4, 4, Comment),
      (5, 3, Type),
    ] {
    assert_eq(
      highlights.line(line).to_owned(),
      if length == 0 {
        []
      } else {
        [{ start: 0, end: length, kind, }]
      },
    )
  }
  for number in [-1, 0, 6, 99] {
    assert_eq(highlights.line(number).length(), 0)
  }
}

///|
test "line terminators and empty spans never produce colored text" {
  for ending in ["\n", "\r\n", "\r"] {
    let source = "a\{ending}\{ending}b\{ending}"
    let spans : Array[@highlight.HighlightSpan] = []
    @highlight.add_span(spans, 0, 0, 0, Keyword)
    @highlight.add_span(spans, 0, 3, 2, Keyword)
    assert_true(spans.is_empty())
    @highlight.add_span(spans, 1, 0, ending.length() * 2, Comment)
    let highlights = @highlight.SourceHighlights::from_spans(source, spans)
    for number in 1..<=4 {
      assert_eq(highlights.line(number).length(), 0)
    }
  }
  assert_eq(@highlight.SourceHighlights::from_spans("", []).line(1).length(), 0)
  let empty = @highlight.FileHighlights::empty()
  assert_true(empty.old is None && empty.new is None)
}

///|
test "sorting and fragment offsets preserve Chinese and emoji UTF-16 boundaries" {
  let source = "中😀 x\n😀中文"
  let spans : Array[@highlight.HighlightSpan] = []
  @highlight.add_span(spans, 6, 0, 2, StringLiteral)
  @highlight.add_span(spans, 0, 4, 5, Variable)
  @highlight.add_span(spans, 0, 0, 3, Comment)
  @highlight.add_span(spans, 6, 2, 4, StringLiteral)
  let highlights = @highlight.SourceHighlights::from_spans(source, spans)
  assert_eq(highlights.line(1).to_owned(), [
    { start: 0, end: 3, kind: Comment, },
    { start: 4, end: 5, kind: Variable, },
  ])
  assert_eq(highlights.line(2).to_owned(), [
    { start: 0, end: 2, kind: StringLiteral, },
    { start: 2, end: 4, kind: StringLiteral, },
  ])
  for index, line in source.split("\n").to_array() {
    for span in highlights.line(index + 1) {
      assert_false(line[span.start:span.end].is_empty())
    }
  }
}
