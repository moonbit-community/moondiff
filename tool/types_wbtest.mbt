///|
test "DiffOptions clamps negative context lines to zero" {
  let options = DiffOptions::new(context_lines=-1)
  assert_eq(options.context_lines, 0)
  assert_false(options.ignore_comments)
  assert_true(DiffOptions::new(ignore_comments=true).ignore_comments)
}
