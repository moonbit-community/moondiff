///|
/// Highlight raw GitHub Flavored Markdown without rendering it. Offsets are
/// UTF-16 positions in the original source, including mixed newline spellings.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  let candidates : Array[Candidate] = []
  let lines = source_lines(source)
  collect_markdown(source, lines, candidates)
  @highlight.SourceHighlights::from_spans(
    source,
    resolve_candidates(source, candidates),
  )
}
