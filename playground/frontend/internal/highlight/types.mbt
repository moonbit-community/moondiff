///|
// Shared lexical categories rendered by the playground light and dark themes.
pub(all) enum HighlightKind {
  Keyword
  Control
  Async
  Modifier
  Function
  Type
  Package
  Variable
  Number
  Boolean
  StringLiteral
  Escape
  Interpolation
  Comment
  Operator
  Attribute
  AttributeParameter
} derive(Eq, Debug)

///|
// Half-open UTF-16 columns, relative to a source line. Internal collectors use
// the same shape for absolute offsets before indexing the completed source.
pub(all) struct HighlightSpan {
  start : Int
  end : Int
  kind : HighlightKind
} derive(Eq, Debug)

///|
pub struct SourceHighlights {
  lines : Array[Array[HighlightSpan]]
} derive(Eq)

///|
pub(all) struct FileHighlights {
  old : SourceHighlights?
  new : SourceHighlights?
} derive(Eq)

///|
pub fn FileHighlights::empty() -> FileHighlights {
  { old: None, new: None, }
}

///|
// Review rows already carry one-based, original-file line numbers.
pub fn SourceHighlights::line(
  self : SourceHighlights,
  number : Int,
) -> ArrayView[HighlightSpan] {
  match self.lines.get(number - 1) {
    Some(line) => line[:]
    None => []
  }
}
