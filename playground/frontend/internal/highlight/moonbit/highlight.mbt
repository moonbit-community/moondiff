///|
// TextMate categories from moonbit.moonbit-lang 0.7.2026081801. Semantic
// language-server decorations (async/error calls) are deliberately not inferred.
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
pub fn FileHighlights::new(
  old_path : String,
  new_path : String,
  old_source : String,
  new_source : String,
) -> FileHighlights {
  {
    old: if old_path.has_suffix(".mbt") ||
      old_path.has_suffix(".mbtx") ||
      old_path == "pkg.generated.mbti" ||
      old_path.has_suffix("/pkg.generated.mbti") {
      Some(SourceHighlights::from_source(old_source))
    } else {
      None
    },
    new: if new_path.has_suffix(".mbt") ||
      new_path.has_suffix(".mbtx") ||
      new_path == "pkg.generated.mbti" ||
      new_path.has_suffix("/pkg.generated.mbti") {
      Some(SourceHighlights::from_source(new_source))
    } else {
      None
    },
  }
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

///|
pub fn SourceHighlights::from_source(source : String) -> SourceHighlights {
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
  let spans : Array[HighlightSpan] = []
  collect_tokens(source, 0, spans, 0)
  spans.sort_by((a, b) => a.start.compare(b.start))
  let mut line = 0
  for span in spans {
    while line + 1 < starts.length() && starts[line + 1] <= span.start {
      line += 1
    }
    for index = line
        index < starts.length() && starts[index] < span.end
        index = index + 1 {
      let start = Int::max(span.start, starts[index])
      let end = Int::min(span.end, ends[index])
      if start < end {
        lines[index].push({
          start: start - starts[index],
          end: end - starts[index],
          kind: span.kind,
        })
      }
    }
  }
  { lines, }
}

///|
fn add_span(
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

///|
fn slice(source : String, start : Int, end : Int) -> String {
  source[start:end].to_owned()
}
