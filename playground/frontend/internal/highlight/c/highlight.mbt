///|
priv enum Directive {
  None
  Name
  MacroName
  MacroParameters
  HeaderArgument
  Header
  Body
}

///|
priv struct LexicalState {
  mut tag : Bool
  mut attribute : Bool
  mut attribute_depth : Int
  mut attribute_bracket : Int
}

///|
fn LexicalState::new() -> LexicalState {
  { tag: false, attribute: false, attribute_depth: 0, attribute_bracket: -1, }
}

///|
/// Highlight C source using local lexical rules, including C23 syntax.
/// Both sides of conditional compilation are colored. Splicing precedes
/// scanning so continuations work inside identifiers, comments and literals;
/// all returned ranges still refer to the original UTF-16 source.
pub fn highlight(source : String) -> @highlight.SourceHighlights {
  let logical = splice_lines(source)
  let spans = collect_tokens(logical.text)
  @highlight.SourceHighlights::from_spans(source, logical.restore(spans))
}

///|
fn collect_tokens(source : String) -> Array[HighlightSpan] {
  let spans = []
  let mut line_start = true
  let mut directive = Directive::None
  let mut state = LexicalState::new()
  let mut outer_state : LexicalState? = None
  for input = source[:] {
    let start = input.start_offset()
    // Trivia precedes context-sensitive header and attribute recognition.
    // Newlines inside block comments do not reset the surrounding context.
    lexmatch input with longest {
      (re"^" + RE_NEWLINE, after=rest) => {
        line_start = true
        directive = None
        if outer_state is Some(outer) {
          state = outer
          outer_state = None
        }
        continue rest
      }
      (re"^" + RE_SPACE, after=rest) => continue rest
      (re"^" + RE_COMMENT, after=rest) => {
        add_span(spans, 0, start, rest.start_offset(), Comment)
        continue rest
      }
      re"^$" => break
      _ => ()
    }
    let (punctuation, after_punctuation) = punctuation_at(input)
    let end = after_punctuation.start_offset()
    if start == state.attribute_bracket {
      add_span(spans, 0, start, end, Attribute)
      state.attribute_bracket = -1
      line_start = false
      continue after_punctuation
    }
    if line_start && punctuation is Hash {
      add_span(spans, 0, start, end, Control)
      directive = Name
      line_start = false
      // Preprocessing tokens get independent context; incomplete replacement
      // lists must not affect declarations on either side of the directive.
      outer_state = Some(state)
      state = LexicalState::new()
      continue after_punctuation
    }
    line_start = false
    if directive is HeaderArgument {
      directive = Body
      if punctuation is OpenParen {
        directive = Header
        continue after_punctuation
      }
    }
    if directive is Header {
      directive = Body
      if collect_header(input, spans) is Some(rest) {
        continue rest
      }
    }
    lexmatch input with longest {
      (re"^(?:u8|[uUL])?" + (re"['\"]" as quote), after=rest) => {
        if !state.attribute {
          state.tag = false
        }
        continue collect_string(rest, quote, start, spans)
      }
      (re"^" + RE_NUMBER, after=rest) => {
        add_span(spans, 0, start, rest.start_offset(), Number)
        if !state.attribute {
          state.tag = false
        }
        continue rest
      }
      (re"^" + (RE_IDENTIFIER as word), after=rest) => {
        let kind : HighlightKind = match directive {
          Name => {
            directive = match word {
              "define" => MacroName
              "include" | "include_next" | "embed" => Header
              _ => Body
            }
            Control
          }
          MacroName => {
            directive = if punctuation_at(rest).0 is OpenParen {
              MacroParameters
            } else {
              Body
            }
            Function
          }
          MacroParameters => Variable
          _ if state.attribute =>
            if state.attribute_depth == 0 {
              Attribute
            } else {
              AttributeParameter
            }
          _ if state.tag => Type
          Body if word is ("__has_include" | "__has_embed") => {
            directive = HeaderArgument
            Control
          }
          Body if word is ("defined" | "__has_c_attribute") => Control
          _ => {
            let kind = word_kind(word)
            if kind is Variable &&
              followed_by_paren(rest, stop_at_newline=!(directive is None)) {
              Function
            } else {
              kind
            }
          }
        }
        add_span(spans, 0, start, rest.start_offset(), kind)
        if !state.attribute {
          state.tag = kind is Keyword && word is ("struct" | "enum" | "union")
        }
        continue rest
      }
      _ => ()
    }
    if (punctuation is OpenBracket && !state.attribute) ||
      (
        punctuation is CloseBracket &&
        state.attribute &&
        state.attribute_depth == 0
      ) {
      let next = next_token(
        after_punctuation,
        stop_at_newline=!(directive is None),
      )
      let (next_punctuation, rest) = punctuation_at(next)
      if next_punctuation == punctuation {
        state.attribute = punctuation is OpenBracket
        state.attribute_depth = 0
        if next.start_offset() == end {
          add_span(spans, 0, start, rest.start_offset(), Attribute)
          continue rest
        }
        // Attribute brackets are separate C tokens: comments and whitespace
        // between them keep their own scopes and physical source positions.
        add_span(spans, 0, start, end, Attribute)
        state.attribute_bracket = next.start_offset()
        continue after_punctuation
      }
    }
    if state.attribute {
      if punctuation is (OpenParen | OpenBracket | OpenBrace) {
        state.attribute_depth += 1
      } else if punctuation is (CloseParen | CloseBracket | CloseBrace) &&
        state.attribute_depth > 0 {
        state.attribute_depth -= 1
      } else if punctuation is Semicolon && state.attribute_depth == 0 {
        // Recover a missing ]] at the next declaration boundary.
        state.attribute = false
      }
    } else {
      state.tag = false
    }
    if directive is MacroParameters && punctuation is CloseParen {
      directive = Body
    } else if directive is (Name | MacroName) {
      directive = Body
    }
    if punctuation is (Hash | HashHash | Operator) {
      add_span(spans, 0, start, end, Operator)
    }
    continue after_punctuation
  } where {
    proof_invariant: input.start_offset() + input.length() == source.length(),
    proof_reasoning: "Every token consumes a nonempty prefix and resumes at a suffix of the same source; EOF ends the scan.",
  }
  spans
}
