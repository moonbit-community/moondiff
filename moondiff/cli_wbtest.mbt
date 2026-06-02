///|UUID(8bf07bdd-6cbd-4d64-8b82-a40f69970b25)
test "parse_cli_args handles graph limit color flag and files" {
  let options = parse_cli_args(["-g", "42", "--no-color", "old.mbt", "new.mbt"]) catch {
    _ => panic()
  }
  assert_true(options.graph_limit_text == "42")
  assert_true(options.use_color == false)
  assert_true(options.old_path == "old.mbt")
  assert_true(options.new_path == "new.mbt")
}
