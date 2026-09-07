///|
/// Calculate a MoonBit source diff without rendering it. AST mode is the
/// default. A fallback is attached directly to the whole or top-level fragment
/// that degraded. In AST mode, text-only changes with no AST change return
/// `NoStructuralChanges`; pure declaration reordering returns `Reordered` and
/// preserves both source orders. In a sectioned Lexical result, each changed
/// declaration-owned range is emitted in full and is not cropped by
/// `DiffOptions.context_lines`; unchanged declaration sections remain empty.
/// A change confined to whitespace-only lines outside those ranges returns
/// `NoStructuralChanges`. A `Whole` lexical result compares every source line
/// with the requested context radius.
///
/// `old_name` and `new_name` are paths used for test-file filtering and parser
/// diagnostics. With `ignore_tests`, either path ending in `_test.mbt` or
/// `_wbtest.mbt` ignores the entire pair before parsing, including additions,
/// deletions, and renames. Matching is case-sensitive. Identical sources still
/// return `Identical`; otherwise an ignored pair returns `IgnoredOnly` with an
/// empty `Whole` document, no fallbacks, and `ignore_reason() == Some(TestFile)`.
/// Omitted names default to "old" and "new", so only the existing top-level
/// test-block filtering applies. Content-only filtering reports
/// `Some(FilteredContent)`; all statuses other than `IgnoredOnly` have no
/// ignore reason.
///
/// ```mbt check
/// test {
///   let result = diff(
///     "fn helper() { 1 }",
///     "fn helper() { 2 }",
///     old_name="helper_test.mbt",
///     new_name="helper.mbt",
///     options=DiffOptions(ignore_tests=true),
///   )
///   assert_true(result.status() is IgnoredOnly)
///   assert_true(result.ignore_reason() is Some(TestFile))
/// }
/// ```
pub fn diff(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  options? : DiffOptions = Default::default(),
) -> DiffResult {
  if options.ignore_tests &&
    (@diff_ignore.is_test_file(old_name) || @diff_ignore.is_test_file(new_name)) {
    return @model.DiffResult::make(
      Whole({ document: { hunks: [], }, fallbacks: [], }),
      if old_source == new_source {
        Identical
      } else {
        IgnoredOnly
      },
      ignore_reason=TestFile,
    )
  }
  let mode = match options.mode {
    Ast => @alignment.AlignedDiffMode::Ast
    Lexical => @alignment.AlignedDiffMode::Lexical
  }
  let result = @alignment.calculate_diff_document(
    old_source,
    new_source,
    old_name~,
    new_name~,
    context=options.context_lines,
    graph_limit=options.graph_limit,
    ignore_comments=options.ignore_comments,
    ignore_tests=options.ignore_tests,
    mode~,
  )
  @model.DiffResult::make(result.document, result.status)
}
