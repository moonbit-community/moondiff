///|
test "pending storage removal matches the exact string operation ID" {
  assert_true(viewed_storage_matches("{\"id\":\"123\"}", "123"))
  assert_false(viewed_storage_matches("{\"id\":\"124\"}", "123"))
  assert_false(viewed_storage_matches("{\"id\":123}", "123"))
  assert_false(viewed_storage_matches("{}", "123"))
  assert_false(viewed_storage_matches("[]", "123"))
  try viewed_storage_matches("null", "123") catch {
    InvalidStoredViewedRecord => ()
    _ => fail("expected invalid stored record")
  } noraise {
    _ => fail("null must fail storage cleanup")
  }
  try viewed_storage_matches("invalid JSON", "123") catch {
    _ => ()
  } noraise {
    _ => fail("malformed JSON must fail storage cleanup")
  }
}
