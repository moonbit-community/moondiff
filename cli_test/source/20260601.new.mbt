test "debug inspect error path" {
  try @debug.debug_inspect(1) catch {
    _ => ()
  } noraise {
    _ => fail("expected debug_inspect failure")
  }
 }