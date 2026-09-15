///|
// TextMate categories from moonbit.moonbit-lang 0.7.2026081801. Semantic
// language-server decorations (async/error calls) are deliberately not inferred.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  let spans : Array[HighlightSpan] = []
  collect_tokens(source, 0, spans, 0)
  @highlight.SourceHighlights::from_spans(source, spans)
}

///|
fn slice(source : String, start : Int, end : Int) -> String {
  source[start:end].to_owned()
}
