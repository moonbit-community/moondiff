///|
// YAML 1.2 Core schema, https://yaml.org/spec/1.2.2/#103-core-schema.
// Resolve the whole plain scalar, never a numeric prefix. In particular,
// signed hex/octal, binary, timestamps, underscores and YAML 1.1 booleans
// are strings. Tags are lexical properties and do not override these scopes.
fn scalar_kind(input : StringView) -> HighlightKind {
  lexmatch input with longest {
    re"^(?:null|Null|NULL|~)$" => Keyword
    re"^(?:true|True|TRUE|false|False|FALSE)$" => Boolean
    re"^(?:[\-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$" => Number
    re"^[\-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][\-+]?[0-9]+)?$" => Number
    re"^(?:[\-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$" => Number
    _ => StringLiteral
  }
}

///|
fn plain_line_end(source : String, start : Int, end : Int, flow : Bool) -> Int {
  for i = start; i < end; i = i + 1 {
    if (flow && flow_indicator(source[i])) ||
      (source[i] == '#' && (i == start || source[i - 1] is (' ' | '\t'))) ||
      (source[i] == ':' && mapping_colon(source[i:], flow)) {
      return i
    }
  }
  end
}

///|
// A plain scalar can continue across blank lines and indented physical lines.
// Look ahead one line at a time so numeric-looking first lines are classified
// only after the entire scalar is known. Comments terminate plain scalars.
fn collect_plain(
  source : String,
  lines : Array[SourceLine],
  row : Int,
  start : Int,
  parent_indent : Int,
  flow : Bool,
) -> (StringView, StringView) {
  let mut end = plain_line_end(source, start, lines[row].end, flow)
  let mut content_end = end_offset(source[start:end].trim_end(chars=" \t"))
  let mut current = row
  while end == lines[current].end {
    let mut next = current + 1
    while next < lines.length() &&
          source[lines[next].start:lines[next].end].trim(chars=" \t").is_empty() {
      next += 1
    }
    if next == lines.length() {
      break
    }
    let line = lines[next]
    let text = source[line.start:line.end].trim_start(chars=" \t")
    if (!flow && line.indent <= parent_indent) ||
      text[0] == '#' ||
      (
        text.start_offset() == line.start &&
        (document_marker(text) || text[0] == '%')
      ) {
      break
    }
    let next_end = plain_line_end(source, text.start_offset(), line.end, flow)
    // A mapping entry starts another node; it cannot continue a plain value.
    if next_end == text.start_offset() ||
      (next_end < line.end && source[next_end] == ':') {
      break
    }
    end = next_end
    content_end = end_offset(
      source[text.start_offset():end].trim_end(chars=" \t"),
    )
    current = next
  }
  (source[start:content_end], source[end:])
}
