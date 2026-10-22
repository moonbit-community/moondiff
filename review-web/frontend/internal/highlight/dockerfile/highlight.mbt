///|
/// Tolerantly highlight Dockerfile syntax at original UTF-16 offsets.
/// Parser directives, logical continuations, JSON forms, shell fragments and
/// heredocs are scanned before shared per-line and per-source budgets apply.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  @highlight.SourceHighlights::from_spans(source, collect_tokens(source))
}

///|
fn collect_tokens(source : String) -> Array[HighlightSpan] {
  let spans = []
  let lines = source_lines(source)
  let pending : Array[PendingHeredoc] = []
  let mut instruction : InstructionState? = None
  let mut escape : UInt16 = '\\'
  let mut parser_allowed = true
  let mut syntax_seen = false
  let mut escape_seen = false
  let mut check_seen = false
  for index, line in lines {
    if instruction is None && !pending.is_empty() {
      let heredoc = pending[0]
      let content_start = heredoc_content_start(
        source,
        line,
        heredoc.strip_tabs,
      )
      if is_heredoc_delimiter(source, line, heredoc) {
        add_span(spans, 0, content_start, line.end, Control)
        let _ = pending.remove(0)
      } else if heredoc.shell {
        scan_shell(
          source,
          line.start,
          line.end,
          heredoc.shell_state,
          heredoc.expand,
          [],
          spans,
        )
        if heredoc.shell_state.quote is Unquoted {
          heredoc.shell_state.command = true
        }
      } else {
        scan_interpolated_text(
          source,
          line.start,
          line.end,
          StringLiteral,
          heredoc.expand,
          spans,
        )
      }
      continue
    }

    let mut content_start = skip_space(source, line.start, line.end)
    if index == 0 &&
      content_start < line.end &&
      source[content_start] == '\uFEFF' {
      content_start = skip_space(source, content_start + 1, line.end)
    }
    if instruction is None && parser_allowed {
      match parser_directive(source, line, spans) {
        Some((key, value_start, value_end)) => {
          let duplicate = match key {
            "syntax" => syntax_seen
            "escape" => escape_seen
            _ => check_seen
          }
          if duplicate {
            // Replace directive scopes with the normal top-level comment.
            while spans.last() is Some(span) && span.start >= content_start {
              let _ = spans.pop()
            }
            add_span(spans, 0, content_start, line.end, Comment)
            parser_allowed = false
          } else {
            match key {
              "syntax" => syntax_seen = true
              "escape" => {
                escape_seen = true
                let value = source[value_start:value_end].trim(chars=" \t")
                if value.length() == 1 && value[0] is ('\\' | '`') {
                  escape = value[0]
                }
              }
              _ => check_seen = true
            }
          }
          continue
        }
        None => ()
      }
    }
    if content_start == line.end {
      if instruction is None {
        parser_allowed = false
      }
      continue
    }
    if source[content_start] == '#' {
      add_span(spans, 0, content_start, line.end, Comment)
      if instruction is None {
        parser_allowed = false
      }
      // A comment inside a continued instruction is removed without ending it.
      continue
    }

    if instruction is None {
      parser_allowed = false
      let name_end = ascii_word_end(source, content_start, line.end)
      if name_end == content_start ||
        !is_instruction(source[content_start:name_end]) {
        continue
      }
      let root = source[content_start:name_end].to_upper().to_owned()
      add_span(
        spans,
        0,
        content_start,
        name_end,
        if root == "ONBUILD" {
          Control
        } else {
          Keyword
        },
      )
      instruction = Some(InstructionState::new(root))
      content_start = name_end
    }

    let logical_end = trim_space_end(source, content_start, line.end)
    let continued = logical_end > content_start &&
      source[logical_end - 1] == escape
    let segment_end = if continued { logical_end - 1 } else { line.end }
    if instruction is Some(state) {
      scan_instruction_segment(
        source, content_start, segment_end, state, pending, spans,
      )
    }
    if continued {
      add_span(spans, 0, logical_end - 1, logical_end, Escape)
    } else {
      instruction = None
    }
  }
  spans
}
