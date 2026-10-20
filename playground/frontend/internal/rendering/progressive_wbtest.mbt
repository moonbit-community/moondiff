///|
test "progressive range covers the viewport and one screen ahead without expanding past files" {
  assert_false(in_expansion_range(-100, 0, 720))
  assert_true(in_expansion_range(-10, 20, 720))
  assert_true(in_expansion_range(719, 750, 720))
  assert_true(in_expansion_range(1439, 1480, 720))
  assert_false(in_expansion_range(1440, 1480, 720))
  assert_false(in_expansion_range(800, 850, 400))
  assert_false(in_expansion_range(0, 0, 0))
}
