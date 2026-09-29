///|
priv struct Candidate {
  start : Int
  end : Int
  kind : HighlightKind
  priority : Int
}

///|
fn candidate(
  candidates : Array[Candidate],
  start : Int,
  end : Int,
  kind : HighlightKind,
  priority : Int,
) -> Unit {
  if start < end {
    candidates.push({ start, end, kind, priority, })
  }
}

///|
// Resolve lexical layers at UTF-16 code-unit granularity. Every scanner only
// introduces boundaries at existing source boundaries, so compression cannot
// split a surrogate pair. Later, higher-priority tokens replace lower layers.
fn resolve_candidates(
  source : String,
  candidates : Array[Candidate],
) -> Array[HighlightSpan] {
  candidates.sort_by((a, b) => a.priority.compare(b.priority))
  let kinds : Array[HighlightKind?] = Array::make(source.length(), None)
  for item in candidates {
    let start = Int::max(0, item.start)
    let end = Int::min(source.length(), item.end)
    for cursor in start..<end {
      if !(source[cursor] is ('\r' | '\n')) {
        kinds[cursor] = Some(item.kind)
      }
    }
  }
  let spans : Array[HighlightSpan] = []
  let mut cursor = 0
  while cursor < kinds.length() {
    match kinds[cursor] {
      None => cursor += 1
      Some(kind) => {
        let start = cursor
        cursor += 1
        while cursor < kinds.length() && kinds[cursor] == Some(kind) {
          cursor += 1
        }
        add_span(spans, 0, start, cursor, kind)
      }
    }
  }
  spans
}
