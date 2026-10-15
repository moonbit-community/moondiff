///|
fn test_span(
  line : Int32,
  start_col : Int32,
  end_col : Int32,
) -> @span.SingleLineSpan {
  { line, start_col, end_col, }
}

///|
fn assert_mapped(
  mapping : @diff_ignore.SpanMapping,
  line : Int32,
  start_col : Int32,
  end_col : Int32,
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

///|
test "restoring excluded text and source indexes preserves intraline status" {
  let old_source = "// old heading\nlet old = 1 // old explanation"
  let new_source = "// new heading\n\nlet new = 2 // new explanation"
  let old = @diff_ignore.SourceView::from_source(
    old_source,
    ignore_comments=true,
  )
  let new = @diff_ignore.SourceView::from_source(
    new_source,
    ignore_comments=true,
  )
  for intraline in [@model.NotComputed, Computed] {
    let document : @model.HunkDocument = {
      hunks: [
        {
          old_start: 0,
          old_len: 1,
          new_start: 0,
          new_len: 1,
          blocks: [
            ChangeBlock([
              Paired(
                {
                  index: 0,
                  segments: [{ kind: Unchanged, text: old.lines()[0], }],
                  intraline,
                },
                {
                  index: 0,
                  segments: [{ kind: Unchanged, text: new.lines()[0], }],
                  intraline,
                },
              ),
            ]),
          ],
        },
      ],
    }
    let restored = @diff_ignore.restore_document(document, old~, new~)
    let changes = restored.hunks[0].blocks.filter(block => {
      block is ChangeBlock(_)
    })
    guard changes is [ChangeBlock([Paired(old_line, new_line)])] else {
      fail("expected a restored code change beside excluded headings")
    }
    assert_eq((old_line.index, new_line.index), (1, 2))
    assert_eq(old_line.text(), "let old = 1 // old explanation")
    assert_eq(new_line.text(), "let new = 2 // new explanation")
    assert_true(old_line.intraline == intraline)
    assert_true(new_line.intraline == intraline)
    assert_true(old_line.segments.any(segment => segment.kind is Ignored))
    assert_true(new_line.segments.any(segment => segment.kind is Ignored))
  }
}
