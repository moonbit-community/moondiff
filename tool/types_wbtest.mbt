///|
test "DiffOptions clamps negative context lines to zero" {
  let options = DiffOptions::new(context_lines=-1)
  assert_eq(options.context_lines, 0)
}
