///|
priv struct FlowContext {
  mapping : Bool
  mut key : Bool
  column : Int
}

///|
fn push_block(blocks : Array[(Int, Bool)], indent : Int, key : Bool) -> Unit {
  while blocks.last() is Some((previous, _)) && previous >= indent {
    let _ = blocks.pop()
  }
  blocks.push((indent, key))
}

///|
/// Highlight YAML using YAML 1.2 Core scalar rules and tolerant lexical state.
/// Tags and aliases are colored without resolution. All spans refer to the
/// original UTF-16 source; shared rendering budgets are applied after scanning.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  @highlight.SourceHighlights::from_spans(source, collect_tokens(source))
}

///|
fn collect_tokens(source : String) -> Array[HighlightSpan] {
  let spans = []
  let lines = source_lines(source)
  let flow : Array[FlowContext] = []
  // Block frames record the indentation of the owning ':' / '-' / '?' node,
  // including compact mappings in sequences, rather than the value column.
  let blocks : Array[(Int, Bool)] = []
  let mut row = 0
  let mut context_row = -1
  let mut node_column = -1
  let mut key_column = -1
  let mut adjacent_end = -1
  for input = source[:] {
    let start = input.start_offset()
    while row + 1 < lines.length() && start >= lines[row].next {
      row += 1
    }
    lexmatch input with longest {
      (re"^[ \t\r\n\uFEFF]+", after=rest) => continue rest
      (re"^#[^\r\n]*", after=rest) => {
        add_span(spans, 0, start, rest.start_offset(), Comment)
        continue rest
      }
      re"^$" => break
      _ => ()
    }
    let line = lines[row]
    if context_row != row {
      if flow.is_empty() {
        while blocks.last() is Some((indent, _)) && indent >= line.indent {
          let _ = blocks.pop()
        }
      }
      node_column = -1
      key_column = -1
      context_row = row
    }
    if node_column < 0 {
      node_column = start - line.start
    }
    // Quoted scalars can cross lines before this loop updates its row.
    let adjacent = adjacent_end >= line.start && adjacent_end <= line.end
    adjacent_end = -1
    if start == line.start && document_marker(input) {
      add_span(spans, 0, start, start + 3, Control)
      blocks.clear()
      flow.clear()
      node_column = -1
      key_column = -1
      continue input[3:]
    }
    if start == line.start && input[0] == '%' {
      let directive = source[start:line.end]
      let comment = comment_offset(directive)
      add_span(
        spans,
        0,
        start,
        end_offset(directive[:comment].trim_end(chars=" \t")),
        Control,
      )
      add_span(spans, 0, start + comment, line.end, Comment)
      continue source[line.end:]
    }
    let in_flow = !flow.is_empty()
    let parent_indent = blocks.last().map(frame => frame.0).unwrap_or(-1)
    let key = match flow.last() {
      Some(frame) => frame.key
      None => blocks.last().map(frame => frame.1).unwrap_or(false)
    }
    if mapping_colon(input, in_flow) || (in_flow && adjacent && input[0] == ':') {
      add_span(spans, 0, start, start + 1, Operator)
      if flow.last() is Some(frame) {
        frame.key = false
      } else {
        push_block(
          blocks,
          if key_column >= 0 {
            key_column
          } else {
            line.indent
          },
          false,
        )
      }
      node_column = -1
      key_column = -1
      continue input[1:]
    }
    if (
        input[0] == '?' &&
        (
          separated(input[1:]) ||
          (in_flow && input.length() > 1 && flow_indicator(input[1]))
        )
      ) ||
      (!in_flow && input[0] == '-' && separated(input[1:])) {
      add_span(spans, 0, start, start + 1, Operator)
      if flow.last() is Some(frame) {
        frame.key = true
      } else {
        push_block(blocks, start - line.start, input[0] == '?')
      }
      node_column = -1
      key_column = -1
      continue input[1:]
    }
    lexmatch input with longest {
      (re"^[\[{]" as char, after=rest) => {
        let mapping = char == '{'
        flow.push({ mapping, key: mapping, column: node_column, })
        add_span(spans, 0, start, rest.start_offset(), Operator)
        node_column = -1
        continue rest
      }
      (re"^[\]}]", after=rest) => {
        if flow.pop() is Some(frame) {
          node_column = frame.column
          if followed_by_colon(rest, !flow.is_empty(), true) {
            key_column = frame.column
          }
        }
        add_span(spans, 0, start, rest.start_offset(), Operator)
        adjacent_end = rest.start_offset()
        continue rest
      }
      (re"^,", after=rest) =>
        if flow.last() is Some(frame) {
          frame.key = frame.mapping
          add_span(spans, 0, start, rest.start_offset(), Operator)
          node_column = -1
          continue rest
        }
      (re"^[&*][^ \t\r\n\[\]{},]*", after=rest) => {
        add_span(spans, 0, start, rest.start_offset(), Attribute)
        if followed_by_colon(rest, in_flow, false) {
          key_column = node_column
        }
        continue rest
      }
      (re"^!(?:<[^>\r\n]*>?|[^ \t\r\n\[\]{},]*)", after=rest) => {
        add_span(spans, 0, start, rest.start_offset(), Type)
        if followed_by_colon(rest, in_flow, false) {
          key_column = node_column
        }
        continue rest
      }
      _ => ()
    }
    if input[0] is ('\'' | '"') {
      let first = spans.length()
      let rest = if input[0] == '"' {
        collect_double_quoted(input, spans)
      } else {
        collect_single_quoted(input, spans)
      }
      if key || followed_by_colon(rest, in_flow, true) {
        for index in first..<spans.length() {
          let span = spans[index]
          if span.kind is StringLiteral {
            spans[index] = { ..span, kind: Variable, }
          }
        }
        key_column = node_column
      }
      adjacent_end = rest.start_offset()
      continue rest
    }
    if !in_flow && block_header(input) is Some(header) {
      continue collect_block(
          source,
          lines,
          row,
          header,
          parent_indent,
          if key {
            Variable
          } else {
            StringLiteral
          },
          spans,
        )
    }
    let (scalar, rest) = collect_plain(
      source, lines, row, start, parent_indent, in_flow,
    )
    let kind : HighlightKind = if key || followed_by_colon(rest, in_flow, false) {
      key_column = node_column
      Variable
    } else {
      scalar_kind(scalar)
    }
    add_span(spans, 0, start, end_offset(scalar), kind)
    continue rest
  } where {
    proof_invariant: input.start_offset() + input.length() == source.length(),
    proof_reasoning: "Each token consumes a nonempty prefix at character boundaries; scalar collectors preserve physical offsets and EOF ends the scan.",
  }
  spans
}
