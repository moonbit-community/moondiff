///|
/// Calculate a MoonBit source diff without rendering it. AST mode is the
/// default. Parsing, graph, or internal computation limits degrade to lexical
/// documents and are described by typed fallback metadata. In AST mode,
/// text-only changes with no AST change return `NoStructuralChanges` and an
/// empty document. Optional source names are forwarded to parser diagnostics.
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
  let calculation = @alignment.calculate_diff_document(
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
  let result = calculation.result
  {
    document: result.document,
    status: result.status,
    fallbacks: result.fallbacks,
    layout: calculation.layout,
  }
}
