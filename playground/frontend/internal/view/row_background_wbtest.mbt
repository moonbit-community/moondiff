///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "neutral cells and gutters require completed comparisons in either layout" {
  let refined : @model.DiffLine = {
    index: 0,
    segments: [{ kind: Unchanged, text: "same", }],
    intraline: Computed,
  }
  let plain : @model.DiffLine = { ..refined, intraline: NotComputed, }
  let blank : @model.DiffLine = { ..refined, index: 1, segments: [], }
  let inserted_blank : @model.DiffLine = { ..blank, intraline: NotComputed, }
  let changed : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Changed, text: "new", }],
    intraline: Computed,
  }
  let document : @model.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 2,
        new_start: 0,
        new_len: 3,
        blocks: [
          ChangeBlock([
            Paired(refined, plain),
            OldOnly(blank),
            NewOnly(inserted_blank),
            NewOnly(changed),
          ]),
        ],
      },
    ],
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for mode in [@change.Split, Unified] {
    let rendered = render_test_html(() => {
      safe_review_diff(
        fixture_file("target.mbt", "modified"),
        0,
        document,
        mode,
        @comments.Session::new().read_view(),
        emit,
      )
    })
    // The two verified old lines have neutral code cells and their gutters.
    assert_eq(rendered.split("class=\"del diff-neutral\"").count() - 1, 2)
    assert_eq(
      rendered.split("diff-neutral").count() - 1,
      if mode is Split {
        4
      } else {
        6
      },
    )
    assert_false(rendered.contains("class=\"add diff-neutral\""))
    assert_true(rendered.contains("<b class=\"wa\">"))
  }
}
