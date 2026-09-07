///|
test "CLI ignores test file pairs before mixed-type and dev null dispatch" {
  for
    paths in [
      ("old_test.mbt", "new.mbt"),
      ("old.mbt", "new_wbtest.mbt"),
      ("old_wbtest.mbt", "new.txt"),
      ("old.txt", "new_test.mbt"),
      ("/dev/null", "new_test.mbt"),
      ("old_wbtest.mbt", "/dev/null"),
    ] {
    let (old_path, new_path) = paths
    let old = if old_path == "/dev/null" { "" } else { "fn broken( {" }
    let new = if new_path == "/dev/null" { "" } else { "fn broken( [" }
    for ignore_comments in [false, true] {
      let options = @cli_diff.Options::new(ignore_tests=true, ignore_comments~)
      assert_eq(
        @cli_diff.render(old_path, old, new_path, new, options~),
        "--- \{old_path}\n+++ \{new_path}\nTest file comparison ignored (--ignore-tests).\n",
      )
      assert_eq(
        @cli_diff.render(old_path, "", new_path, "", options~),
        "--- \{old_path}\n+++ \{new_path}\nNo changes.\n",
      )
    }
    let unfiltered = @cli_diff.render(old_path, old, new_path, new)
    assert_false(unfiltered.contains("comparison ignored"))
    assert_true(unfiltered.contains("@@"), msg=unfiltered)
  }
}

///|
test "mixed ordinary file pairs retain plain output when filters are enabled" {
  // Parsing a 5,000-term addition can overflow the stack. These ordinary
  // mixed-file comparisons must reach the plain text diff without parsing.
  let addition = Array::make(4_999, "1").join(" + ")
  let sources = [
    ("test { old_value() }", "test { new_value() }"),
    ("// old comment", "// new comment"),
    ("fn helper() { 1 }", "fn helper() {\n  1\n}"),
    ("fn first() {}\nfn second() {}", "fn second() {}\nfn first() {}"),
    ("fn broken( {", "fn broken( ["),
    (
      "fn sum() -> Int { \{addition} + 1 }\n",
      "fn sum() -> Int { \{addition} + 2 }\n",
    ),
  ]
  for
    paths in [
      ("old.mbt", "new.txt"),
      ("old.txt", "new.mbt"),
      ("/dev/null", "new.mbt"),
      ("old.mbt", "/dev/null"),
      ("old_test.txt", "new_test.txt"),
      ("old_TEST.mbt", "new.txt"),
    ] {
    let (old_path, new_path) = paths
    for source_pair in sources {
      let (old_source, new_source) = source_pair
      let old = if old_path == "/dev/null" { "" } else { old_source }
      let new = if new_path == "/dev/null" { "" } else { new_source }
      let expected = @cli_diff.render(old_path, old, new_path, new)
      assert_true(expected.contains("@@"), msg=expected)
      for ignore_comments in [false, true] {
        let actual = @cli_diff.render(
          old_path,
          old,
          new_path,
          new,
          options=@cli_diff.Options::new(ignore_tests=true, ignore_comments~),
        )
        assert_eq(actual, expected)
      }
    }
  }
}
