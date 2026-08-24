///|
/// Calculate an AST-first MoonBit source diff without rendering it. Parsing,
/// graph, or internal computation limits degrade to lexical documents and are
/// described by typed fallback metadata. Text-only changes with no AST change
/// return `NoStructuralChanges` and an empty document.
pub fn diff(
  old_source : String,
  new_source : String,
  options? : DiffOptions = Default::default(),
) -> DiffResult {
  let result = @alignment.diff_document_detailed(
    old_source,
    new_source,
    context=options.context_lines,
    graph_limit=options.graph_limit,
    ignore_comments=options.ignore_comments,
    ignore_tests=options.ignore_tests,
  )
  {
    document: result.document,
    status: result.status,
    fallbacks: result.fallbacks,
  }
}
