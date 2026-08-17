///|UUID(8bf07bdd-6cbd-4d64-8b82-a40f69970b25)
test "parse_cli_args handles graph limit color comment flags and files" {
  let options = parse_cli_args([
    "-g", "42", "--no-color", "--ignore-comments", "old.mbt", "new.mbt",
  ]) catch {
    _ => panic()
  }
  assert_true(options.graph_limit_text == "42")
  assert_true(options.use_color == false)
  assert_true(options.ignore_comments)
  assert_true(options.old_path == "old.mbt")
  assert_true(options.new_path == "new.mbt")

  let defaults = parse_cli_args(["old.mbt", "new.mbt"]) catch { _ => panic() }
  assert_false(defaults.ignore_comments)
}

///|
test "parse_graph_limit accepts values representable as Int" {
  assert_eq(parse_graph_limit("0"), 0U)
  assert_eq(parse_graph_limit("2147483647"), 2147483647U)
}

///|
test "parse_graph_limit rejects negative values" {
  let result = parse_graph_limit("-1") catch {
    error => {
      assert_true(
        error.to_string().contains("graph limit must be non-negative"),
      )
      0U
    }
  }
  assert_eq(result, 0U)
}

///|
test "parse_graph_limit rejects values larger than Int" {
  let result = parse_graph_limit("2147483648") catch { _ => 0U }
  assert_eq(result, 0U)
}

///|UUID(5fbce824-f73c-4607-8f3e-81cd9195dc4f)
test "moondiff command help uses README command name" {
  let help = moondiff_command().render_help()
  assert_true(
    help.has_prefix("Usage: moondiff [options] <old-file> <new-file>"),
  )
  assert_false(help.contains("Usage: astdiff"))
  assert_true(help.contains("--ignore-comments"))
  assert_true(
    help.contains("Ignore MoonBit comment-only and blank-line-only differences"),
  )
}

///|UUID(f4c874ad-006a-41cb-ab86-0013549f7845)
test "should_use_structural_diff requires both inputs to be mbt files" {
  assert_true(should_use_structural_diff("old.mbt", "new.mbt"))
  assert_false(should_use_structural_diff("old.txt", "new.mbt"))
  assert_false(should_use_structural_diff("old.mbt", "new.txt"))
}

///|UUID(fad12a14-0144-4f4f-8891-706c7971b622)
test "render_cli_diff uses regular line diff for non-mbt paths" {
  let options = CliOptions::{
    old_path: "old.txt",
    new_path: "new.txt",
    graph_limit_text: "0",
    use_color: false,
    ignore_comments: true,
  }
  let rendered = render_cli_diff(options, "plain old\n", "plain new\n", 0)
  assert_false(rendered.has_prefix("note: fallback to line diff"))
  assert_false(rendered.has_prefix("note: fallback to tokdiff"))
  assert_true(rendered.has_prefix("--- old.txt\n+++ new.txt\n@@ -1"))
  assert_true(rendered.contains("1 . plain old"))
  assert_true(rendered.contains(". 1 plain new"))
}

///|
test "render_cli_diff reports ignored MoonBit blank-line changes" {
  let options = CliOptions::{
    old_path: "old.mbt",
    new_path: "new.mbt",
    graph_limit_text: "0",
    use_color: false,
    ignore_comments: true,
  }
  let rendered = render_cli_diff(
    options, "fn stable() {}", "fn stable() {}\n\n\u{2003}", 0,
  )
  assert_eq(
    rendered, "--- old.mbt\n+++ new.mbt\nNo changes besides comments or blank lines.\n",
  )
}
