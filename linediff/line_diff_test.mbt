///|
test "negative context is identical to zero context" {
  let old = [
    "alpha old omega", "same one", "same two", "same three", "beta old omega",
  ]
  let new = [
    "alpha new omega", "same one", "same two", "same three", "beta new omega",
  ]
  assert_true(
    @linediff.line_diff(old~, new~, context=-7) ==
    @linediff.line_diff(old~, new~, context=0),
  )
}
