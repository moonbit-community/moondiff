///|
extern "js" fn same_highlights(
  a : @highlight_moonbit.FileHighlights,
  b : @highlight_moonbit.FileHighlights,
) -> Bool =
  #| (a, b) => a === b

///|
test "source highlights are computed once across all diff options" {
  let initial = ready_test_file(
    fixture_file("src/code.mbt", "modified"),
    ["fn value() { 1 // before", "}"],
    ["fn value() { 22 // after", "}"],
  )
  assert_true(initial.diff_cache.highlights is None)
  let mut file = ensure_file_document(initial, LexicalAlgorithm)
  let highlights = file.diff_cache.highlights.unwrap()
  assert_true(highlights.old is Some(_))
  assert_true(highlights.new is Some(_))
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
  assert_true(initial.diff_cache.highlights is None)
}

///|
test "highlights wait for source and remain available for fallback diffs" {
  let initial = ready_test_file(
    fixture_file("src/broken.mbt", "modified"),
    ["fn incomplete( { let x = 1"],
    ["fn incomplete( [ let x = 2"],
  )
  for
    state in [
      NotRequested,
      Loading,
      LoadFailed("retry"),
      CannotRender("binary", false),
    ] {
    let pending = ensure_file_document(
      { ..initial, old_side: state, },
      AstAlgorithm,
    )
    assert_true(pending.diff_cache.highlights is None)
  }
  let fallback = ensure_file_document(initial, AstAlgorithm)
  let highlights = fallback.diff_cache.highlights.unwrap()
  assert_true(highlights.old.unwrap().line(1).length() > 0)
  assert_true(highlights.new.unwrap().line(1).length() > 0)
  for (old, new) in [("code.mbt", "code.txt"), ("code.txt", "code.mbt")] {
    let renamed = ensure_file_document(
      ready_test_file(
        fixture_file(new, "renamed", previous_filename=old),
        ["let x = 1"],
        ["let x = 2"],
      ),
      AstAlgorithm,
    )
    let highlights = renamed.diff_cache.highlights.unwrap()
    assert_eq(highlights.old is Some(_), old.has_suffix(".mbt"))
    assert_eq(highlights.new is Some(_), new.has_suffix(".mbt"))
  }
}
