///|
test "semantic HTML convenience renderers equal direct IR renderers" {
  let old = [
    "before semantic anchor", "call(alpha, old, omega)", "", "after semantic anchor",
  ]
  let new = [
    "before semantic anchor", "call(", "  alpha,", "  fresh,", "  omega,", ")", "after semantic anchor",
  ]
  let cleaned = @tokdiff.diff(old~, new~, context=1, line_cleanup=true)
  let raw = @tokdiff.diff(old~, new~, context=0, line_cleanup=false)
  assert_eq(
    @render_html.render_side_by_side(cleaned, line_numbers=true),
    @render_html.side_by_side_html(
      old~,
      new~,
      context=1,
      line_cleanup=true,
      line_numbers=true,
    ),
  )
  assert_eq(
    @render_html.render_unified(raw, line_numbers=false),
    @render_html.unified_html(
      old~,
      new~,
      context=0,
      line_cleanup=false,
      line_numbers=false,
    ),
  )
  assert_eq(
    @render_html.render_side_by_side_hunks(raw),
    @render_html.side_by_side_hunks_html(old~, new~, context=0),
  )
  assert_eq(
    @render_html.render_unified_hunks(raw, line_numbers=true),
    @render_html.unified_hunks_html(old~, new~, context=0, line_numbers=true),
  )
}

///|
test "plain HTML convenience renderers equal direct IR renderers" {
  for
    pair in [
      (([] : Array[String]), ["x", ""]),
      (["x", ""], ([] : Array[String])),
      (["same", "old", "tail"], ["same", "new", "extra", "tail"]),
    ] {
    let (old, new) = pair
    let document = @tokdiff.line_diff(old~, new~, context=0)
    assert_eq(
      @render_html.render_side_by_side(document, line_numbers=true),
      @render_html.side_by_side_line_html(
        old~,
        new~,
        context=0,
        line_numbers=true,
      ),
    )
    assert_eq(
      @render_html.render_unified(document),
      @render_html.unified_line_html(old~, new~, context=0),
    )
  }
}
