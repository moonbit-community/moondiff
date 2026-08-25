///|
fn renderer_fixture() -> @model.DiffDocument {
  let old_line : @model.DiffLine = {
    index: 1,
    segments: [
      { kind: Changed, text: "<old>" },
      { kind: Ignored, text: " // old" },
    ],
  }
  let new_line : @model.DiffLine = {
    index: 1,
    segments: [
      { kind: Changed, text: "&new" },
      { kind: Ignored, text: " // new" },
    ],
  }
  let old_ignored : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Ignored, text: "// old docs" }],
  }
  let new_ignored : @model.DiffLine = {
    index: 2,
    segments: [{ kind: Ignored, text: "// new docs" }],
  }
  {
    hunks: [
      {
        old_start: 0,
        old_len: 3,
        new_start: 0,
        new_len: 3,
        blocks: [
          ContextBlock([{ old_index: 0, new_index: 0, text: "a < b" }]),
          ChangeBlock([Paired(old_line, new_line)]),
          IgnoredBlock([Paired(old_ignored, new_ignored)]),
        ],
      },
    ],
  }
}

///|
test "pure split renderer escapes text and preserves changed and ignored kinds" {
  let rendered = @html.render_side_by_side(
    renderer_fixture(),
    line_numbers=true,
  )
  assert_true(rendered.contains("a &lt; b"), msg=rendered)
  assert_true(
    rendered.contains("<b class=\"wd\">&lt;old&gt;</b>"),
    msg=rendered,
  )
  assert_true(rendered.contains("<b class=\"wa\">&amp;new</b>"), msg=rendered)
  assert_true(rendered.contains("class=\"ignored-context\""), msg=rendered)
  assert_true(rendered.contains("old-line-number\">2</td>"), msg=rendered)
  assert_true(rendered.contains("new-line-number\">2</td>"), msg=rendered)
  assert_eq(
    @html.render_side_by_side_hunks(renderer_fixture(), line_numbers=true),
    [rendered],
  )
}

///|
test "pure unified renderer orders changes and wraps a standalone page" {
  let rendered = @html.render_unified(renderer_fixture(), line_numbers=true)
  let old_position = rendered.find("&lt;old&gt;").unwrap()
  let new_position = rendered.find("&amp;new").unwrap()
  assert_true(old_position < new_position, msg=rendered)
  assert_true(rendered.contains("class=\"ctx ignored\""), msg=rendered)
  assert_eq(@html.render_unified_hunks(renderer_fixture(), line_numbers=true), [
    rendered,
  ])
  let page = @html.html_page(title="<diff & review>", rendered)
  assert_true(
    page.contains("<title>&lt;diff &amp; review&gt;</title>"),
    msg=page,
  )
  assert_true(page.contains(rendered), msg=page)
}
