///|
fn token_kind(token : @tokens.Token) -> HighlightKind? {
  match token {
    ASYNC => Some(Async)
    BREAK
    | CONTINUE
    | RAISE
    | THROW
    | TRY
    | CATCH
    | AS
    | ELSE
    | IF
    | MATCH
    | USING
    | WHILE
    | RETURN
    | LOOP
    | GUARD
    | GUARD_EXCLAMATION
    | DEFER
    | ERRDEFER
    | FOR
    | IN
    | IS
    | NORAISE
    | NOCANCEL
    | NOBREAK
    | TRY_QUESTION
    | TRY_EXCLAMATION
    | LEXMATCH
    | LEXMATCH_QUESTION
    | LEXSCAN => Some(Control)
    PUB | PRIV | READONLY | EXTERN | MUTABLE => Some(Modifier)
    IMPORT
    | STRUCT
    | ENUM
    | TRAIT
    | DERIVE
    | IMPL
    | WITH
    | TYPEALIAS
    | TRAITALIAS
    | FNALIAS
    | FN
    | LET
    | VAR
    | CONST
    | TYPE
    | TEST
    | SUBERROR
    | AND
    | LETREC
    | ENUMVIEW
    | EXTENUM
    | DECLARE
    | WHERE
    | EXTEND
    | PACKAGE
    | PROOF_ASSERT
    | PROOF_LET
    | FORALL
    | EXISTS
    | IMPLIES => Some(Keyword)
    THIN_ARROW | FAT_ARROW => Some(Keyword)
    TRUE | FALSE => Some(Boolean)
    INT(_) | FLOAT(_) | DOUBLE(_) | DOT_INT(_) => Some(Number)
    UIDENT(_) | DOT_UIDENT(_) => Some(Type)
    PACKAGE_NAME(_) => Some(Package)
    LIDENT("except") => Some(Control)
    LIDENT("recur") => Some(Keyword)
    LIDENT("not") => Some(Operator)
    LIDENT(_) | UNDERSCORE | POST_LABEL(_) | POST_LABEL_TRANSPARENT(_) =>
      Some(Variable)
    INFIX1(_)
    | INFIX2(_)
    | INFIX3(_)
    | INFIX4(_)
    | AUGMENTED_ASSIGNMENT(_)
    | PLUS_EQUAL
    | EQUAL
    | EQ_TILDE
    | MINUS
    | PLUS
    | BAR
    | AMPERAMPER
    | AMPER
    | CARET
    | BARBAR
    | PIPE
    | PIPE_LEFT
    | LT_PLUS
    | LT_QUESTION => Some(Operator)
    _ => None
  }
}

///|
fn is_function(tokens : ArrayView[@tokens.Triple], index : Int) -> Bool {
  if index > 0 && tokens[index - 1].0 is FN {
    return true
  }
  if index >= 3 &&
    tokens[index - 1].0 is COLONCOLON &&
    tokens[index - 2].0 is UIDENT(_) &&
    tokens[index - 3].0 is FN {
    return true
  }
  for next = index + 1; next < tokens.length(); next = next + 1 {
    match tokens[next].0 {
      COMMENT(_) | EXCLAMATION | QUESTION => continue
      LPAREN => return true
      _ => return false
    }
  }
  false
}

///|
fn collect_tokens(
  source : String,
  offset : Int,
  spans : Array[HighlightSpan],
  depth : Int,
  attribute? : Bool = false,
) -> Unit {
  // Bound recursive embedded code; a partial highlight still preserves text.
  if depth >= 32 {
    return
  }
  let result = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
  )
  // Lexical errors do not discard valid tokens elsewhere in an incomplete file.
  let tokens = result.tokens.filter(triple => {
    let (token, start, end) = triple
    !(token is (EOF | NEWLINE)) &&
    start.cnum < end.cnum &&
    start.cnum >= 0 &&
    end.cnum <= source.length()
  })
  for index = 0; index < tokens.length(); {
    let (token, start_pos, end_pos) = tokens[index]
    let start = start_pos.cnum
    let end = end_pos.cnum
    match token {
      COMMENT(_) if slice(source, start, end).has_prefix("///") => {
        let mut next = index + 1
        while next < tokens.length() &&
              tokens[next].0 is COMMENT(_) &&
              tokens[next].1.lnum == tokens[next - 1].2.lnum + 1 &&
              slice(source, tokens[next].1.cnum, tokens[next].2.cnum).has_prefix(
                "///",
              ) &&
              slice(source, tokens[next - 1].2.cnum, tokens[next].1.cnum)
              .trim()
              .is_empty() {
          next += 1
        }
        collect_docs(source, tokens[index:next], offset, spans, depth)
        continue next
      }
      COMMENT(_) => add_span(spans, offset, start, end, Comment)
      ATTRIBUTE(_) => {
        let mut name_end = start + 1
        while name_end < end &&
              (
                source[name_end] == '.' ||
                source[name_end] == '_' ||
                (source[name_end] >= 'a' && source[name_end] <= 'z') ||
                (source[name_end] >= 'A' && source[name_end] <= 'Z') ||
                (source[name_end] >= '0' && source[name_end] <= '9')
              ) {
          name_end += 1
        }
        add_span(spans, offset, start, name_end, Attribute)
        collect_tokens(
          slice(source, name_end, end),
          offset + name_end,
          spans,
          depth + 1,
          attribute=true,
        )
      }
      CHAR(_) | BYTE(_) | STRING(_) | BYTES(_) | REGEX_LITERAL(_) =>
        collect_string(source, start, end, [], offset, spans, depth)
      INTERP(elems) | BYTES_INTERP(elems) | REGEX_INTERP(elems) =>
        collect_string(source, start, end, elems, offset, spans, depth)
      MULTILINE_STRING(_) => {
        add_span(spans, offset, start, start + 2, Operator)
        add_span(spans, offset, start + 2, end, StringLiteral)
      }
      MULTILINE_INTERP(elems) => {
        add_span(spans, offset, start, start + 2, Operator)
        collect_string(source, start + 2, end, elems, offset, spans, depth)
      }
      _ => {
        let attribute_word = attribute &&
          (lexmatch source[start:end] {
            re"^[A-Za-z0-9_.]+$" => true
            _ => false
          })
        let kind = if attribute_word {
          Some(AttributeParameter)
        } else if token is (LIDENT(_) | DOT_LIDENT(_)) &&
          is_function(tokens, index) &&
          (token_kind(token) == Some(Variable) || token is DOT_LIDENT(_)) {
          Some(Function)
        } else {
          token_kind(token)
        }
        if kind is Some(kind) {
          let end = match token {
            POST_LABEL(_) => end - 1
            POST_LABEL_TRANSPARENT(_) => end - 2
            _ => end
          }
          add_span(spans, offset, start, end, kind)
        }
      }
    }
    continue index + 1
  }
}
