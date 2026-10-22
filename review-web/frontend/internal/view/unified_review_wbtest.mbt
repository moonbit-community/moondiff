///|
fn neutral_review_row_fixture() -> ReviewRow {
  {
    file_index: 0,
    old_line: Some(3),
    new_line: Some(5),
    old_text: Some("  let x"),
    new_text: Some("let x"),
    old_segments: Some([{ kind: Unchanged, text: "  let x", }]),
    new_segments: Some([{ kind: Unchanged, text: "let x", }]),
    old_intraline: Some(Computed),
    new_intraline: Some(Computed),
    kind: ChangeRow,
    change_block_start: true,
    old_anchor: None,
    new_anchor: None,
  }
}

///|
test "neutral review sides require computed segments without nonempty changes" {
  let cases : Array[(ArrayView[@model.DiffSegment]?, Bool)] = [
    (None, false),
    (Some([]), true),
    (Some([{ kind: Unchanged, text: "same", }]), true),
    (Some([{ kind: Ignored, text: "// comment", }]), true),
    (Some([{ kind: Changed, text: "", }]), true),
    (Some([{ kind: Changed, text: " ", }]), false),
    (Some([{ kind: Changed, text: "new", }]), false),
  ]
  for kind in [@review.ChangeRow, ContextRow, IgnoredRow] {
    for status in [Some(@model.Computed), Some(NotComputed), None] {
      for (segments, neutral) in cases {
        assert_eq(
          review_side_is_neutral(kind, status, segments),
          kind is ChangeRow && status is Some(Computed) && neutral,
        )
      }
    }
  }
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "Unified neutral pairs show new source and syntax with both original line numbers" {
  let row = neutral_review_row_fixture()
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let highlights : @highlight.FileHighlights = {
    old: Some(
      @highlight.SourceHighlights::from_spans("\n\n  let x", [
        { start: 2, end: 9, kind: Comment, },
      ]),
    ),
    new: Some(
      @highlight.SourceHighlights::from_spans("\n\n\n\nlet x", [
        { start: 4, end: 7, kind: Keyword, },
      ]),
    ),
  }
  for
    (old, new, expected) in [
      (
        row.old_segments,
        row.new_segments,
        "<span><span class=\"syntax-keyword\">let</span> x</span>",
      ),
      (
        row.new_segments,
        row.new_segments,
        "<span><span class=\"syntax-keyword\">let</span> x</span>",
      ),
      (
        Some([{ kind: Ignored, text: "// before", }]),
        Some([{ kind: Ignored, text: "// after", }]),
        "<span class=\"ignored-context\">// after</span>",
      ),
      (Some([]), Some([]), ""),
      (
        Some([{ kind: Changed, text: "", }]),
        Some([{ kind: Changed, text: "", }]),
        "<b class=\"wa\"></b>",
      ),
    ] {
    let highlights = if new is Some(segments) &&
      segments.any(segment => segment.kind is Ignored) {
      @highlight.FileHighlights::empty()
    } else {
      highlights
    }
    let row = {
      ..row,
      old_text: old.map(segments => {
        segments.map(segment => segment.text).join("")
      }),
      new_text: new.map(segments => {
        segments.map(segment => segment.text).join("")
      }),
      old_segments: old,
      new_segments: new,
    }
    let rendered = render_test_html(() => {
      @html.table([
        @html.tbody(
          Map::from_array(
            unified_review_line(
              row,
              @comments.Session::new().read_view(),
              emit,
              highlights~,
              change_block=7,
            ),
          ),
        ),
      ])
    })
    assert_eq(rendered.split("<tr").count() - 1, 1)
    assert_true(rendered.contains("class=\"diff-neutral-pair\""))
    assert_true(rendered.contains("data-change-block-start=\"7\""))
    assert_true(rendered.contains("<td class=\"ctx\">\{expected}</td>"))
    for (side, number) in [("old", 3), ("new", 5)] {
      assert_true(
        rendered.contains(
          "\{side}-line-number\"><span class=\"line-number-value\">\{number}</span>",
        ),
      )
    }
    assert_false(rendered.contains("diff-prefix"))
    assert_false(rendered.contains("syntax-comment"))
  }
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "Unified keeps unrefined changed unpaired and ignored source rows separate" {
  let row = neutral_review_row_fixture()
  let changed : ArrayView[@model.DiffSegment]? = Some([
    { kind: Changed, text: "changed", },
  ])
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for
    (selected, count, old_prefix, new_prefix) in [
      ({ ..row, old_intraline: Some(NotComputed), }, 2, true, true),
      ({ ..row, new_intraline: Some(NotComputed), }, 2, true, true),
      ({ ..row, old_intraline: None, }, 2, true, true),
      ({ ..row, new_intraline: None, }, 2, true, true),
      ({ ..row, old_segments: None, }, 2, true, true),
      ({ ..row, new_segments: None, }, 2, true, true),
      ({ ..row, old_segments: changed, }, 2, true, true),
      ({ ..row, new_segments: changed, }, 2, true, true),
      ({ ..row, new_line: None, }, 1, true, false),
      ({ ..row, old_line: None, }, 1, false, true),
      ({ ..row, kind: IgnoredRow, }, 2, false, false),
    ] {
    let rendered = render_test_html(() => {
      @html.table([
        @html.tbody(
          Map::from_array(
            unified_review_line(
              selected,
              @comments.Session::new().read_view(),
              emit,
            ),
          ),
        ),
      ])
    })
    assert_eq(rendered.split("<tr").count() - 1, count)
    assert_false(rendered.contains("diff-neutral-pair"))
    assert_eq(rendered.contains("class=\"diff-prefix\">-"), old_prefix)
    assert_eq(rendered.contains("class=\"diff-prefix\">+"), new_prefix)
  }
}
