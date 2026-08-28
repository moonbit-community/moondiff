///|
fn test_span(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> @span.SingleLineSpan {
  { line, start_col, end_col, }
}

///|
fn assert_mapped(
  mapping : @diff_ignore.SpanMapping,
  line : Int,
  start_col : Int,
  end_col : Int,
) -> Unit raise {
  guard mapping is Mapped(span) else { fail("expected a mapped span") }
  assert_eq(
    (span.line, span.start_col, span.end_col),
    (line, start_col, end_col),
  )
}

///|
test "span mapping distinguishes mapped filtered and zero-width ranges" {
  let plain = @diff_ignore.SourceView::from_lines(["abc"])
  assert_mapped(plain.map_span(test_span(1, 1, 4)), 1, 1, 4)
  assert_mapped(plain.map_span(test_span(1, 0, 3)), 1, 1, 4)
  assert_mapped(plain.map_span(test_span(1, 0, 4)), 1, 1, 4)
  assert_true(plain.map_span(test_span(1, 1, 1)) is Filtered)
  assert_true(plain.map_span(test_span(1, 4, 4)) is Filtered)
  assert_true(plain.map_span(test_span(1, 0, 0)) is Filtered)

  let comments = @diff_ignore.SourceView::from_source(
    "abc // note\n// hidden",
    ignore_comments=true,
  )
  assert_mapped(comments.map_span(test_span(1, 1, 4)), 1, 1, 4)
  assert_true(comments.map_span(test_span(1, 5, 7)) is Filtered)
  assert_true(comments.map_span(test_span(2, 1, 3)) is Filtered)
  assert_true(comments.map_span(test_span(2, 1, 99)) is OutOfBounds)
}

///|
test "span mapping rejects invalid line and column ranges" {
  let view = @diff_ignore.SourceView::from_lines(["abc"])
  for
    span in [
      test_span(-1, 1, 2),
      test_span(0, 1, 2),
      test_span(2, 1, 2),
      test_span(1, -1, 2),
      test_span(1, 3, 2),
      test_span(1, 1, 5),
      test_span(1, 5, 5),
      test_span(1, 0, 5),
    ] {
    assert_true(view.map_span(span) is OutOfBounds)
  }
}

///|
test "sliced views validate global line numbers before remapping" {
  let view = @diff_ignore.SourceView::from_lines(["first", "second"]).slice(
    1, 1,
  )
  assert_mapped(view.map_span(test_span(2, 1, 7)), 1, 1, 7)
  assert_true(view.map_span(test_span(1, 1, 2)) is OutOfBounds)
}
