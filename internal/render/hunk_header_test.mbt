///|
test "canonical hunk ranges" {
  assert_eq(@render.hunk_header(0, 1, 0, 1), "@@ -1 +1 @@")
  assert_eq(@render.hunk_header(0, 0, 0, 2), "@@ -0,0 +1,2 @@")
  assert_eq(@render.hunk_header(6, 0, 12, 1), "@@ -6,0 +13 @@")
}
