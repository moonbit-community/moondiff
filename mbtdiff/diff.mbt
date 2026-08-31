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
/// with the requested context radius. Optional source names are forwarded to
/// parser diagnostics.
pub fn diff(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  options? : DiffOptions = Default::default(),
) -> DiffResult {
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
