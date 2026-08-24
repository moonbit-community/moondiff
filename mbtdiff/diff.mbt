///|
/// Calculate a MoonBit source diff without rendering it. AST mode is the
/// default. Parsing, graph, or internal computation limits degrade to lexical
/// documents and are described by typed fallback metadata. In AST mode,
/// text-only changes with no AST change return `NoStructuralChanges` and an
/// empty document.
pub fn diff(
  old_source : String,
  new_source : String,
  options? : DiffOptions = Default::default(),
) -> DiffResult {
  let mode = match options.mode {
    Ast => @alignment.AlignedDiffMode::Ast
    Lexical => @alignment.AlignedDiffMode::Lexical
  }
  let result = @alignment.diff_document_detailed(
    old_source,
    new_source,
    context=options.context_lines,
    graph_limit=options.graph_limit,
    ignore_comments=options.ignore_comments,
    ignore_tests=options.ignore_tests,
    mode~,
  )
  {
    document: result.document,
    status: result.status,
    fallbacks: result.fallbacks,
  }
}
