///|
test "semantic convenience renderers equal direct IR renderers" {
  let old = [
    "before semantic anchor", "call(alpha, old, omega)", "", "after semantic anchor",
  ]
  let new = [
    "before semantic anchor", "call(", "  alpha,", "  fresh,", "  omega,", ")", "after semantic anchor",
  ]
  let cleaned = @tokdiff.diff(old~, new~, context=1, line_cleanup=true)
  let raw = @tokdiff.diff(old~, new~, context=0, line_cleanup=false)
  assert_eq(
    @tokdiff_html.render_side_by_side(cleaned, line_numbers=true),
    @tokdiff_html.side_by_side_html(
      old~,
      new~,
      context=1,
      line_cleanup=true,
      line_numbers=true,
    ),
  )
  assert_eq(
    @tokdiff_html.render_unified(raw, line_numbers=false),
    @tokdiff_html.unified_html(
      old~,
      new~,
      context=0,
      line_cleanup=false,
      line_numbers=false,
    ),
  )
  assert_eq(
    @tokdiff_html.render_side_by_side_hunks(raw),
    @tokdiff_html.side_by_side_hunks_html(old~, new~, context=0),
  )
  assert_eq(
    @tokdiff_html.render_unified_hunks(raw, line_numbers=true),
    @tokdiff_html.unified_hunks_html(old~, new~, context=0, line_numbers=true),
  )
  assert_eq(
    @tokdiff_text.render_unified_hunks(
      @tokdiff.diff(old~, new~, context=0, line_cleanup=true),
    ),
    @tokdiff_text.unified_hunks(old~, new~, context=0, line_cleanup=true),
  )
}

///|
test "plain convenience renderers equal direct IR renderers" {
  for
    pair in [
      (([] : Array[String]), ["x", ""]),
      (["x", ""], ([] : Array[String])),
      (["same", "old", "tail"], ["same", "new", "extra", "tail"]),
    ] {
    let (old, new) = pair
    let document = @tokdiff.line_diff(old~, new~, context=0)
    assert_eq(
      @tokdiff_html.render_side_by_side(document, line_numbers=true),
      @tokdiff_html.side_by_side_line_html(
        old~,
        new~,
        context=0,
        line_numbers=true,
      ),
    )
    assert_eq(
      @tokdiff_html.render_unified(document),
      @tokdiff_html.unified_line_html(old~, new~, context=0),
    )
    assert_eq(
      @tokdiff_text.render_unified_hunks(document),
      @tokdiff_text.unified_line_hunks(old~, new~, context=0),
    )
  }
}
