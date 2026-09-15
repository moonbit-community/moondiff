///|
priv struct SplicedSource {
  text : String
  // (logical offset, total removed UTF-16 units), in source order.
  splices : Array[(Int, Int)]
}

///|
fn splice_lines(source : String) -> SplicedSource {
  let text = StringBuilder()
  let splices = []
  for input = source[:], removed = 0 {
    lexmatch input {
      (re"\\" + RE_NEWLINE, before=plain, after=rest) => {
        text.write_view(plain)
        let logical = input.start_offset() + plain.length() - removed
        let removed = rest.start_offset() - logical
        splices.push((logical, removed))
        continue rest, removed
      }
      _ =>
        if splices.is_empty() {
          break { text: source, splices, }
        } else {
          text.write_view(input)
          break { text: text.to_string(), splices, }
        }
    }
  } where {
    proof_invariant: 0 <= removed && removed <= input.start_offset(),
    proof_reasoning: "Each match removes one whole continuation and resumes after it; removed counts only earlier UTF-16 units.",
  }
}

///|
fn SplicedSource::restore(
  self : SplicedSource,
  spans : Array[HighlightSpan],
) -> Array[HighlightSpan] {
  if self.splices.is_empty() {
    return spans
  }
  let restored = []
  let mut splice = 0
  let mut removed = 0
  for span in spans {
    while splice < self.splices.length() && self.splices[splice].0 <= span.start {
      removed = self.splices[splice].1
      splice += 1
    }
    let start = span.start + removed
    while splice < self.splices.length() &&
          (self.splices[splice].0 < span.end || span.end == self.text.length()) {
      removed = self.splices[splice].1
      splice += 1
    }
    add_span(restored, 0, start, span.end + removed, span.kind)
  }
  restored
}
