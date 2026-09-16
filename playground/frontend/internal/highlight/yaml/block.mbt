///|
fn block_header(input : StringView) -> StringView? {
  lexmatch input with longest {
    (re"^[|>](?:[1-9][+\-]?|[+\-][1-9]?)?" as header, after=rest) => {
      // Do not mistake plain or unfinished text such as "|word" for a block.
      if !separated(rest) {
        return None
      }
      lexmatch rest with longest {
        (re"^[ \t]*(?:#[^\r\n]*)?(?:\r\n|[\r\n]|$)", after=_) => Some(header)
        _ => None
      }
    }
    _ => None
  }
}

///|
fn collect_block(
  source : String,
  lines : Array[SourceLine],
  row : Int,
  header : StringView,
  parent_indent : Int,
  kind : HighlightKind,
  spans : Array[HighlightSpan],
) -> StringView {
  add_span(spans, 0, header.start_offset(), end_offset(header), Operator)
  let tail = source[end_offset(header):lines[row].end].trim_start(chars=" \t")
  if !tail.is_empty() {
    add_span(spans, 0, tail.start_offset(), end_offset(tail), Comment)
  }
  let base = Int::max(0, parent_indent)
  let mut indent : Int? = None
  for char in header {
    if char is ('1'..='9') {
      indent = Some(base + char.to_int() - '0'.to_int())
    }
  }
  let start = lines[row].next
  let mut end = start
  for next in (row + 1)..<lines.length() {
    let line = lines[next]
    let blank = line.start + line.indent == line.end
    if !blank {
      if indent is None {
        if line.indent <= base {
          break
        }
        indent = Some(line.indent)
      }
      if line.indent < indent.unwrap() {
        break
      }
    }
    end = line.next
  }
  // Chomping affects the decoded value, not the source's lexical scope. The
  // original indentation and trailing blank lines remain string content.
  add_span(spans, 0, start, end, kind)
  source[end:]
}
