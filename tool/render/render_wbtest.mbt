///|UUID(0b20b38d-173f-4f3e-8ef0-96c593744b36)
fn render_whole_line_span(line : Int, text : String) -> @span.SingleLineSpan {
  @span.SingleLineSpan::{ line, start_col: 1, end_col: text.length() + 1 }
}

///|UUID(8fa8d071-722a-4291-b20e-7a1121eff9e1)
fn render_unchanged_line(
  line : Int,
  text : String,
  opposite_line : Int,
  opposite_text : String,
) -> @syntax.MatchedPos {
  @syntax.MatchedPos::{
    kind: @syntax.MatchKind::Unchanged(opposite_pos=[
      render_whole_line_span(opposite_line, opposite_text),
    ]),
    pos: render_whole_line_span(line, text),
  }
}

///|UUID(52a99f4e-072b-4416-a8f0-2d11d9d60a38)
fn render_novel_span(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> @syntax.MatchedPos {
  @syntax.MatchedPos::{
    kind: @syntax.MatchKind::Novel,
    pos: @span.SingleLineSpan::{ line, start_col, end_col },
  }
}

///|
test "RenderOptions clamps negative context lines to zero" {
  let options = RenderOptions::new(context_lines=-1)
  assert_eq(options.context_lines, 0)
  let rendered = render_line_diff(
    "old.txt",
    "unchanged before\nold value\nunchanged after",
    "new.txt",
    "unchanged before\nnew value\nunchanged after",
    None,
    None,
    options,
  )
  assert_true(rendered.contains("old value"))
  assert_true(rendered.contains("new value"))
  assert_false(rendered.contains("unchanged before"))
  assert_false(rendered.contains("unchanged after"))
}

///|UUID(cb822c15-f51a-4177-bfaf-a6b59daae2eb)
test "render_ast_diff uses one merged hunk for nearby ast changes" {
  let old_source =
    #|fn a() {
    #|  foo(bar)
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(beta)
    #|}
  let new_source =
    #|fn a() {
    #|  foo(baz(bar))
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(gamma(beta))
    #|}
  let old_lines = split_lines(old_source)
  let new_lines = split_lines(new_source)
  let lhs_positions = [
    render_unchanged_line(1, old_lines[0], 1, new_lines[0]),
    render_unchanged_line(2, old_lines[1], 2, new_lines[1]),
    render_unchanged_line(3, old_lines[2], 3, new_lines[2]),
    render_unchanged_line(5, old_lines[4], 5, new_lines[4]),
    render_unchanged_line(7, old_lines[6], 7, new_lines[6]),
    render_unchanged_line(8, old_lines[7], 8, new_lines[7]),
    render_unchanged_line(9, old_lines[8], 9, new_lines[8]),
  ]
  let rhs_positions = [
    render_unchanged_line(1, new_lines[0], 1, old_lines[0]),
    render_unchanged_line(2, new_lines[1], 2, old_lines[1]),
    render_novel_span(2, 7, 10),
    render_unchanged_line(3, new_lines[2], 3, old_lines[2]),
    render_unchanged_line(5, new_lines[4], 5, old_lines[4]),
    render_unchanged_line(7, new_lines[6], 7, old_lines[6]),
    render_unchanged_line(8, new_lines[7], 8, old_lines[7]),
    render_novel_span(8, 9, 14),
    render_unchanged_line(9, new_lines[8], 9, old_lines[8]),
  ]
  let rendered = render_ast_diff(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    lhs_positions,
    rhs_positions,
    RenderOptions::new(context_lines=3),
  )

  @debug.assert_eq(rendered.split("@@").count(), 3)
  assert_true(rendered.contains("5 5 fn mid() {}"))
  assert_true(rendered.contains(". 2   foo(baz(bar))"))
  assert_true(rendered.contains(". 8   alpha(gamma(beta))"))
  assert_false(rendered.contains("+   2   foo(baz(bar))"))
  assert_false(rendered.contains("+   8   alpha(gamma(beta))"))
}

///|UUID(0d1a0a7b-5a0d-4d9e-8fd3-e90428d09cc1)
test "display_line_no colors missing placeholder dots gray for every line style" {
  @debug.assert_eq(
    display_line_no(None, 2, 1, Deleted, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, 1, Added, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, 1, Context, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(display_line_no(None, 2, 1, Added, false), "..")
}
