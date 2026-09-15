///|
fn counted_line_highlights(counts : Array[Int]) -> @highlight.SourceHighlights {
  let source = StringBuilder()
  let spans : Array[@highlight.HighlightSpan] = []
  let mut offset = 0
  for count in counts {
    source.write_string("x ".repeat(count) + "\n")
    for index in 0..<count {
      @highlight.add_span(spans, offset, index * 2, index * 2 + 1, Variable)
    }
    offset += count * 2 + 1
  }
  // Budget allocation follows source order even when the input does not.
  spans.sort_by((a, b) => b.start.compare(a.start))
  @highlight.SourceHighlights::from_spans(source.to_string(), spans)
}

///|
test "line budget keeps the exact limit and drops whole oversized lines" {
  let counts = [1024, 1025, 4096, 0, 2]
  let highlights = counted_line_highlights(counts)
  for index, expected in [1024, 0, 0, 0, 2] {
    assert_eq(highlights.line(index + 1).length(), expected)
  }
  assert_eq(highlights.line(1)[1023], {
    start: 2046,
    end: 2047,
    kind: Variable,
  })
  assert_eq(highlights.line(5).to_owned(), [
    { start: 0, end: 1, kind: Variable, },
    { start: 2, end: 3, kind: Variable, },
  ])
}

///|
test "source budget retains exactly 16384 spans" {
  let counts = Array::make(16, 1024)
  counts.push(1)
  let highlights = counted_line_highlights(counts)
  for line in 1..<=16 {
    assert_eq(highlights.line(line).length(), 1024)
  }
  assert_true(highlights.line(17).is_empty())
}

///|
test "each nonempty line fragment of a multiline span consumes source budget" {
  let source = "x\n".repeat(16385)
  let highlights = @highlight.SourceHighlights::from_spans(source, [
    { start: 0, end: source.length(), kind: Comment, },
  ])
  for line in 1..<=16384 {
    assert_eq(highlights.line(line).to_owned(), [
      { start: 0, end: 1, kind: Comment, },
    ])
  }
  assert_true(highlights.line(16385).is_empty())
  assert_true(highlights.line(16386).is_empty())
}

///|
test "rejected lines leave the remaining source budget for later small lines" {
  let counts = Array::make(15, 1024) + [1025, 1023, 2, 1, 1]
  let highlights = counted_line_highlights(counts)
  for line in 1..<=15 {
    assert_eq(highlights.line(line).length(), 1024)
  }
  for index, expected in [0, 1023, 0, 1, 0] {
    assert_eq(highlights.line(index + 16).length(), expected)
  }
}

///|
test "budgeted multiline spans retain newline and Unicode offsets" {
  for newline in ["\n", "\r\n", "\r"] {
    for count in [1023, 1024] {
      let lines = [
        "中😀",
        "x ".repeat(count) + "/*中😀",
        "续😀*/",
        "int 后😀",
      ]
      let source = lines.join(newline)
      let spans : Array[@highlight.HighlightSpan] = []
      @highlight.add_span(spans, 0, 0, 3, StringLiteral)
      let offset = lines[0].length() + newline.length()
      for index in 0..<count {
        @highlight.add_span(spans, offset, index * 2, index * 2 + 1, Variable)
      }
      let comment_end = offset +
        lines[1].length() +
        newline.length() +
        lines[2].length()
      @highlight.add_span(spans, 0, offset + count * 2, comment_end, Comment)
      @highlight.add_span(spans, comment_end + newline.length(), 0, 3, Type)
      @highlight.add_span(spans, comment_end + newline.length(), 4, 7, Variable)
      let highlights = @highlight.SourceHighlights::from_spans(source, spans)
      assert_eq(highlights.line(1).to_owned(), [
        { start: 0, end: 3, kind: StringLiteral, },
      ])
      assert_eq(
        highlights.line(2).length(),
        if count == 1023 {
          1024
        } else {
          0
        },
      )
      assert_eq(highlights.line(3).to_owned(), [
        { start: 0, end: 5, kind: Comment, },
      ])
      assert_eq(highlights.line(4).to_owned(), [
        { start: 0, end: 3, kind: Type, },
        { start: 4, end: 7, kind: Variable, },
      ])
      for index, line in lines {
        for span in highlights.line(index + 1) {
          assert_false(line[span.start:span.end].is_empty())
          assert_true(line.get_char(span.start) is Some(_))
          assert_true(
            span.end == line.length() || line.get_char(span.end) is Some(_),
          )
        }
      }
    }
  }
}
