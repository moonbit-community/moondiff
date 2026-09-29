///|
test "Markdown additions deletions and renames select each side independently" {
  let cases = [
    ("added.md", "added", "", "# new", true, true),
    ("removed.markdown", "removed", "# old", "", true, true),
    ("new.md", "renamed", "plain", "# heading", false, true),
    ("new.txt", "renamed", "# heading", "plain", true, false),
    (
      "new.markdown", "renamed", "let x = 1", "```mbt\nlet x = 2\n```", true, true,
    ),
  ]
  for
    (path, status, old_source, new_source, old_expected, new_expected) in cases {
    let old_path = match (status, path) {
      ("renamed", "new.md") => "old.txt"
      ("renamed", "new.txt") => "old.md"
      ("renamed", _) => "old.mbt"
      _ => path
    }
    let file = ensure_file_document(
      ready_test_file(
        fixture_file(path, status, previous_filename=old_path),
        old_source.split("\n").map(view => view.to_owned()).to_array(),
        new_source.split("\n").map(view => view.to_owned()).to_array(),
      ),
      LexicalAlgorithm,
    )
    let highlights = file.diff_cache.highlights.unwrap()
    assert_eq(highlights.old is Some(_), old_expected)
    assert_eq(highlights.new is Some(_), new_expected)
  }
}

///|
test "Markdown source highlights and budgets are cached independently per side" {
  let exact = "*x* ".repeat(341) + "\\*"
  let old_source = (exact + "\n").repeat(16) + "# old"
  let new_source = "# new\n" + (exact + "\n").repeat(16) + "tail"
  let initial = ready_test_file(
    fixture_file("README.md", "modified"),
    old_source.split("\n").map(view => view.to_owned()).to_array(),
    new_source.split("\n").map(view => view.to_owned()).to_array(),
  )
  let mut file = ensure_file_document(initial, LexicalAlgorithm)
  let highlights = file.diff_cache.highlights.unwrap()
  assert_eq(highlights.old.unwrap().line(16).length(), 1024)
  assert_true(highlights.old.unwrap().line(17).is_empty())
  assert_true(highlights.new.unwrap().line(1).length() > 0)
  assert_eq(highlights.new.unwrap().line(16).length(), 1024)
  assert_true(highlights.new.unwrap().line(17).is_empty())
  for algorithm in [LexicalAlgorithm, AstAlgorithm] {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        file = ensure_file_document(
          file,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
        assert_true(
          same_highlights(highlights, file.diff_cache.highlights.unwrap()),
        )
      }
    }
  }
}
