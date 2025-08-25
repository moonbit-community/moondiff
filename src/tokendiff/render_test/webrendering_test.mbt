///|
test "fn_insert_funcall" (t : @test.T) {
  test_web_rendering(t, "fn_insert_funcall")
}

///|
test "fn_insert_comments" (t : @test.T) {
  test_web_rendering(t, "fn_insert_comments")
}

///|
test "fn_modify_then_insert" (t : @test.T) {
  // TODO: fix this on postopt
  test_web_rendering(t, "fn_modify_then_insert")
}

///|
test "struct_modify_field_type_and_delete_field" (t : @test.T) {
  test_web_rendering(t, "struct_modify_field_type_and_delete_field")
}

///|
test "fn_insert_errorpoly" (t : @test.T) {
  // TODO: fix this on postopt
  test_web_rendering(t, "fn_insert_errorpoly")
}
