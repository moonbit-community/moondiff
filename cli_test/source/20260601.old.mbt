test "debug inspect error path" {
  let result = try! @debug.debug_inspect(1)
  let is_err = match result {
    Ok(_) => false
    Err(_) => true
  }
  inspect(is_err, content="true")
 }
