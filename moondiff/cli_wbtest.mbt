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

///|UUID(5fbce824-f73c-4607-8f3e-81cd9195dc4f)
test "moondiff command help uses README command name" {
  let help = moondiff_command().render_help()
  assert_true(
    help.has_prefix("Usage: moondiff [options] <old-file> <new-file>"),
  )
  assert_false(help.contains("Usage: astdiff"))
}

///|UUID(f4c874ad-006a-41cb-ab86-0013549f7845)
test "should_use_astdiff requires both inputs to be mbt files" {
  assert_true(should_use_astdiff("old.mbt", "new.mbt"))
  assert_false(should_use_astdiff("old.txt", "new.mbt"))
  assert_false(should_use_astdiff("old.mbt", "new.txt"))
}

///|UUID(fad12a14-0144-4f4f-8891-706c7971b622)
test "render_cli_diff uses regular line diff for non-mbt paths" {
  let options = CliOptions::{
    old_path: "old.txt",
    new_path: "new.txt",
    graph_limit_text: "0",
    use_color: false,
  }
  let rendered = render_cli_diff(options, "plain old\n", "plain new\n", 0)
  assert_false(rendered.has_prefix("note: fallback to line diff"))
  assert_true(rendered.has_prefix("--- old.txt\n+++ new.txt\n@@ -1"))
  assert_true(rendered.contains("1 . plain old"))
  assert_true(rendered.contains(". 1 plain new"))
}
