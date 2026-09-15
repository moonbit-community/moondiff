///|
const MAX_LINE_SPANS : Int = 1024

///|
const MAX_SOURCE_SPANS : Int = 16384

///|
/// Index absolute, non-overlapping UTF-16 spans by one-based source line.
/// Spans may be unsorted; the caller's array is not reordered. Line terminators
/// are excluded, including CRLF pairs. Collectors must use character boundaries.
pub fn SourceHighlights::from_spans(
  source : String,
  spans : ArrayView[HighlightSpan],
) -> SourceHighlights {
  let starts = [0]
  let ends : Array[Int] = []
  for i = 0; i < source.length(); {
    if source[i] == '\r' || source[i] == '\n' {
      ends.push(i)
      let next = if source[i] == '\r' &&
        i + 1 < source.length() &&
        source[i + 1] == '\n' {
        i + 2
      } else {
        i + 1
      }
      starts.push(next)
      continue next
    }
    continue i + 1
  }
  ends.push(source.length())
  let lines = Array::makei(starts.length(), _ => [])
  let spans = spans.to_owned()
  spans.sort_by((a, b) => a.start.compare(b.start))
  let mut remaining = MAX_SOURCE_SPANS
  let mut first = 0
  for index in 0..<starts.length() {
    if remaining == 0 {
      break
    }
    while first < spans.length() && spans[first].end <= starts[index] {
      first += 1
    }
    let line = lines[index]
    let limit = Int::min(MAX_LINE_SPANS, remaining)
    for cursor = first
        cursor < spans.length() && spans[cursor].start < ends[index]
        cursor = cursor + 1 {
      let span = spans[cursor]
      let start = Int::max(span.start, starts[index])
      let end = Int::min(span.end, ends[index])
      if start < end {
        // Drop the whole line as soon as it exceeds either budget. Do not
        // keep collecting spans that would create excessive rendering work.
        if line.length() == limit {
          line.clear()
          break
        }
        line.push({
          start: start - starts[index],
          end: end - starts[index],
          kind: span.kind,
        })
      }
    }
    // Only retained lines consume the budget; later smaller lines can fit.
    // Lexical scanning already covered the full source before indexing.
    remaining -= line.length()
  }
  { lines, }
}

///|
/// Append a nonempty span, translating fragment offsets into source offsets.
pub fn add_span(
  spans : Array[HighlightSpan],
  offset : Int,
  start : Int,
  end : Int,
  kind : HighlightKind,
) -> Unit {
  if start < end {
    spans.push({ start: offset + start, end: offset + end, kind, })
  }
}
