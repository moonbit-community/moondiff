///|UUID(0d1a0a7b-5a0d-4d9e-8fd3-e90428d09cc1)
test "display_line_no colors missing placeholder dots gray for every line style" {
  @debug.assert_eq(
    display_line_no(None, 2, Deleted, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, Added, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(
    display_line_no(None, 2, Context, true),
    "\u{1b}[90m..\u{1b}[39m",
  )
  @debug.assert_eq(display_line_no(None, 2, Added, false), "..")
}
