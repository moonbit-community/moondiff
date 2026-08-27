///|UUID(8bf07bdd-6cbd-4d64-8b82-a40f69970b25)
test "parse_cli_args handles graph limit color filter flags and files" {
  let options = parse_cli_args([
    "-g", "42", "--no-color", "--ignore-comments", "--ignore-tests", "old.mbt", "new.mbt",
  ]) catch {
    _ => panic()
  }
  assert_true(options.graph_limit_text == "42")
  assert_true(options.use_color == false)
  assert_true(options.ignore_comments)
  assert_true(options.ignore_tests)
  assert_true(options.old_path == "old.mbt")
  assert_true(options.new_path == "new.mbt")

  let defaults = parse_cli_args(["old.mbt", "new.mbt"]) catch { _ => panic() }
  assert_false(defaults.ignore_comments)
  assert_false(defaults.ignore_tests)
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
  assert_true(help.contains("--ignore-tests"))
  assert_true(
    help.contains("Ignore MoonBit comment-only and blank-line-only differences"),
  )
  assert_true(
    help.contains("Ignore top-level MoonBit test and async test blocks"),
  )
}

///|UUID(fad12a14-0144-4f4f-8891-706c7971b622)
test "render_cli_diff uses regular line diff for non-mbt paths" {
  let options = CliOptions::{
    old_path: "old.txt",
    new_path: "new.txt",
    graph_limit_text: "0",
    use_color: false,
    ignore_comments: true,
    ignore_tests: true,
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
    ignore_tests: false,
  }
  let rendered = render_cli_diff(
    options, "fn stable() {}", "fn stable() {}\n\n\u{2003}", 0,
  )
  assert_eq(
    rendered, "--- old.mbt\n+++ new.mbt\nNo changes besides comments or blank lines.\n",
  )
}

///|
test "render_cli_diff reports ignored MoonBit tests with dynamic descriptions" {
  let old_source = "test \"sample\" { old_value() }"
  let new_source = "test \"sample\" { new_value() }"
  let tests_only = CliOptions::{
    old_path: "old.mbt",
    new_path: "new.mbt",
    graph_limit_text: "0",
    use_color: false,
    ignore_comments: false,
    ignore_tests: true,
  }
  assert_eq(
    render_cli_diff(tests_only, old_source, new_source, 0),
    "--- old.mbt\n+++ new.mbt\nNo changes besides MoonBit test blocks.\n",
  )
  let combined = { ..tests_only, ignore_comments: true }
  assert_eq(
    render_cli_diff(combined, old_source, new_source, 0),
    "--- old.mbt\n+++ new.mbt\nNo changes besides MoonBit test blocks, comments, or blank lines.\n",
  )
}

///|
test "ignore tests preserves CLI layout for files without tests" {
  let defaults = CliOptions::{
    old_path: "old.mbt",
    new_path: "new.mbt",
    graph_limit_text: "3000000",
    use_color: false,
    ignore_comments: false,
    ignore_tests: false,
  }
  let sectioned_old =
    #|///|UUID(first-id)
    #|fn first() { old_value() }
    #|///|UUID(second-id)
    #|fn second() { stable_value() }
  let sectioned_new =
    #|///|UUID(first-id)
    #|fn first() { new_value() }
    #|///|UUID(second-id)
    #|fn second() { stable_value() }
  let cases : Array[(String, String, UInt)] = [
    ("", "fn inserted() { value() }", 3_000_000),
    ("fn deleted() { value() }", "", 3_000_000),
    (sectioned_old, sectioned_new, 3_000_000),
    (
      "fn value() { \"alpha beta gamma\" }", "fn value() { \"alpha zeta gamma\" }",
      0,
    ),
  ]
  for case in cases {
    let (old_source, new_source, graph_limit) = case
    let expected = render_cli_diff(
      defaults, old_source, new_source, graph_limit,
    )
    let actual = render_cli_diff(
      { ..defaults, ignore_tests: true },
      old_source,
      new_source,
      graph_limit,
    )
    assert_eq(actual, expected)
  }
  let sectioned = render_cli_diff(
    defaults, sectioned_old, sectioned_new, 3_000_000,
  )
  assert_true(
    sectioned.contains("[section #1 matched] old lines 1-2; new lines 1-2"),
    msg=sectioned,
  )
  assert_true(sectioned.contains("--- old.mbt: lines 1-2"), msg=sectioned)
  assert_true(sectioned.contains("+++ new.mbt: lines 1-2"), msg=sectioned)
}
