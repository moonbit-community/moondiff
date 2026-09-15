///|
fn syntax_class(kind : @highlight.HighlightKind) -> String {
  let suffix = match kind {
    Keyword => "keyword"
    Control => "control"
    Async => "async"
    Modifier => "modifier"
    Function => "function"
    Type => "type"
    Package => "package"
    Variable => "variable"
    Number => "number"
    Boolean => "boolean"
    StringLiteral => "string"
    Escape => "escape"
    Interpolation => "interpolation"
    Comment => "comment"
    Operator => "operator"
    Attribute => "attribute"
    AttributeParameter => "attribute-parameter"
  }
  "syntax-\{suffix}"
}

///|
fn source_line_highlights(
  source : @highlight.SourceHighlights?,
  line : Int?,
) -> ArrayView[@highlight.HighlightSpan] {
  match (source, line) {
    (Some(source), Some(line)) => source.line(line)
    _ => []
  }
}

///|
// Clip source-line syntax ranges to one diff segment. The outer diff node owns
// the background; these inner nodes only supply foregrounds and font style.
fn syntax_nodes(
  text : String,
  highlights : ArrayView[@highlight.HighlightSpan],
  offset : Int,
) -> Array[@rabbita.Html] {
  let nodes : Array[@rabbita.Html] = []
  let mut cursor = 0
  // Find the first overlapping range without rescanning the whole line for
  // every diff segment (long generated lines can have many tokens and edits).
  let first = for low = 0, high = highlights.length(); low < high; {
    let mid = low + (high - low) / 2
    if highlights[mid].end <= offset {
      continue mid + 1, high
    }
    continue low, mid
  } nobreak {
    low
  }
  for span in highlights[first:] {
    if span.start >= offset + text.length() {
      break
    }
    let start = Int::max(cursor, span.start - offset)
    let end = Int::min(text.length(), span.end - offset)
    if start >= end {
      continue
    }
    if cursor < start {
      nodes.push(@html.text(text[cursor:start].to_owned()))
    }
    nodes.push(
      @html.span(class=syntax_class(span.kind), text[start:end].to_owned()),
    )
    cursor = end
  }
  if cursor < text.length() {
    nodes.push(@html.text(text[cursor:].to_owned()))
  }
  nodes
}
