///|
#warnings("-alert_unstable")
test "only nonempty change blocks mark their first actual source row in either layout" {
  let old : @model.DiffLine = {
    index: 0,
    segments: [{ kind: Changed, text: "old", }],
  }
  let new : @model.DiffLine = {
    index: 0,
    segments: [{ kind: Changed, text: "new", }],
  }
  let blocks : Array[@model.DiffBlock] = [
    ContextBlock([{ old_index: 0, new_index: 0, text: "context", }]),
    ChangeBlock([]),
    ChangeBlock([Paired(old, new), Paired(old, new)]),
    ChangeBlock([OldOnly(old), OldOnly(old)]),
    ChangeBlock([NewOnly(new), NewOnly(new)]),
    IgnoredBlock([Paired(old, old)]),
    IgnoredBlock([Paired(old, new)]),
    IgnoredBlock([OldOnly(old)]),
    IgnoredBlock([NewOnly(new)]),
  ]
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  // Test isolated blocks as well as adjacent independent blocks in one hunk.
  let cases = blocks.map(block => [block])
  cases.push(blocks)
  for selected in cases {
    let hunk : @model.DiffHunk = {
      old_start: 0,
      old_len: 1,
      new_start: 0,
      new_len: 1,
      blocks: selected,
    }
    let count = selected
      .filter(block => block is ChangeBlock(rows) && !rows.is_empty())
      .length()
    for hunks in [[hunk], [hunk, hunk]] {
      for mode in [@change.Split, Unified] {
        for show_hunk_headers in [false, true] {
          let rendered = @rabbita.render_to_string(() => {
            @rabbita.Val::constant(
              safe_review_diff(
                fixture_file("target.mbt", "modified"),
                0,
                { hunks, },
                mode,
                @comments.Session::new(),
                emit,
                show_hunk_headers~,
              ),
            )
          })
          let expected = count * hunks.length()
          assert_eq(
            rendered.split("data-change-block-start").count() - 1,
            expected,
          )
          assert_false(rendered.contains("data-hunk-start"))
          for index in 0..<expected {
            assert_eq(
              rendered.split("data-change-block-start=\"\{index}\"").count() - 1,
              1,
            )
          }
          for row in rendered.split("<tr") {
            if row.contains("data-change-block-start") {
              assert_false(row.contains("hunk-header"))
              assert_true(row.contains("line-number"))
              if selected is [ChangeBlock([Paired(_, _), ..])] {
                // Unified paired changes only mark the deletion row.
                assert_true(row.contains("old"))
              }
            }
          }
        }
      }
    }
  }
}

///|
#warnings("-alert_unstable")
test "section headings leave navigation in the file heading" {
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let hunk = projection_document_fixture().hunks[0]
  for hunks in [[], [hunk], [hunk, hunk]] {
    for expanded in [false, true] {
      let rendered = @rabbita.render_to_string(() => {
        @rabbita.Val::constant(
          semantic_fragment_view(
            fixture_file("target.mbt", "modified"),
            0,
            Some(0),
            { document: { hunks, }, fallbacks: [], },
            Some({ start: 0, len: 1, }),
            Some({ start: 0, len: 1, }),
            None,
            None,
            Split,
            @comments.Session::new(),
            emit,
            false,
            expanded~,
            section_key="stable-key",
          ),
        )
      })
      assert_true(rendered.contains("data-section-key=\"stable-key\""))
      assert_false(rendered.contains("section-change-controls"))
    }
  }
}
