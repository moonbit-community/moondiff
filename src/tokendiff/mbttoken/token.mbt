///|UUID(c67f68f3-145d-4eff-ad80-961857bf0ca1)
pub(all) enum MbtToken {
  Visible(
    kind~ : @tokens.TokenKind,
    loc~ : @basic.Location,
    repr~ : Array[Char]
  )
  Invisible(Array[Int]) // whitespace widths, 0 for newline
  Barrier
}

///|UUID(3b275564-69e2-4725-a6a8-fe6f05a3d97c)
pub impl Show for MbtToken with output(self, logger) {
  match self {
    Visible(kind~, repr~, ..) => {
      logger.write_string("(")
      logger.write_string(kind.to_string())
      logger.write_char(' ')
      logger.write_string(String::from_iter(repr.iter()))
      logger.write_char(')')
    }
    Invisible(repr) => {
      logger.write_string("|")
      logger.write_object(repr)
      logger.write_string("|")
    }
    Barrier => logger.write_string("_")
  }
}

///|UUID(ec039c5a-1378-43a6-87c5-18a01829b4d1)
pub impl ToJson for MbtToken with to_json(self) {
  self.to_string().to_json()
}

///|UUID(6af7c0c1-526f-47b5-a84d-94c0cc97ebf7)
pub impl Eq for MbtToken with equal(self, other) {
  match (self, other) {
    (Invisible(_), Invisible(_))
    | (Barrier, Barrier)
    | (Barrier, Invisible(_))
    | (Invisible(_), Barrier) => true
    (
      Visible(kind=l_kind, repr=l_repr, ..),
      Visible(kind=r_kind, repr=r_repr, ..),
    ) => l_kind == r_kind && l_repr == r_repr
    _ => false
  }
}

///|UUID(fc6fdb12-ac6b-407f-a046-ee9faaf0a0d2)
pub fn MbtToken::to_text(self : MbtToken) -> Array[Char] {
  match self {
    Visible(repr~, ..) => repr
    Invisible(repr) => {
      let output = Array::new()
      for width in repr {
        if width == 0 {
          output.push('\n')
        } else {
          for _ in 0..<width {
            output.push(' ')
          }
        }
      }
      output
    }
    Barrier => Array::new()
  }
}

///|UUID(ba2af0be-f23f-4bed-b1c6-358bc0f5899f)
pub fn MbtToken::emit_text_to(self : MbtToken, buf : Array[Char]) -> Unit {
  match self {
    Visible(repr~, ..) => buf.append(repr)
    Invisible(repr) =>
      for width in repr {
        if width == 0 {
          buf.push('\n')
        } else {
          for _ in 0..<width {
            buf.push(' ')
          }
        }
      }
    Barrier => ()
  }
}

///|UUID(8ef01a12-3cd7-4525-88c3-1e6c34eebc4c)
fn is_continuum(prev : @basic.Position, next : @basic.Position) -> Bool {
  (prev.lnum == next.lnum && prev.column() == next.column()) ||
  (prev.lnum + 1 == next.lnum && next.column() == 1)
}

///|UUID(103524ed-755a-4bee-b4d5-b5be457c82bd)
fn whitespace_width(prev : @basic.Position, next : @basic.Position) -> Int {
  if prev.lnum == next.lnum {
    next.column() - prev.column()
  } else {
    next.column() - 1
  }
}

///|UUID(3cd4a9dc-722f-4b47-afec-bc6cae032df2)
fn is_dot_token(token : @tokens.Token) -> Bool {
  token is DOT_INT(_) ||
  token is DOT_LIDENT(_) ||
  token is DOT_LPAREN ||
  token is DOT_UIDENT(_)
}

///|UUID(23a285d2-4db9-4716-b246-a87b911c7717)
fn Array::add_token(self : Array[MbtToken], token : MbtToken) -> Unit {
  if token is Invisible([w]) && self is [.., last] && last is Invisible(widths) {
    widths.push(w)
  } else {
    self.push(token)
  }
}

///|UUID(02220a38-7942-4c3f-9901-56ae920d40a4)
pub fn MbtToken::from_str(source : String) -> Array[MbtToken] {
  let line_widths = @span.LineWidths::from_str(source)
  let triples = @lexer.tokens_from_string(comment=true, source).tokens
  MbtToken::from_triples(triples, line_widths)
}

///|UUID(a17b85aa-1988-4b89-91f9-7f9846f8b020)
fn MbtToken::from_triples(
  triples : ArrayView[(@tokens.Token, @basic.Position, @basic.Position)],
  line_widths : @span.LineWidths,
) -> Array[MbtToken] {
  let mbt_tokens = Array::new(capacity=triples.length())
  let mut prev_pos = @basic.Position::{
    lnum: 1,
    fname: "dummy",
    bol: 0,
    cnum: 0,
  }
  for triple in triples {
    match triple.0 {
      EOF => break
      SEMI(false) => continue
      NEWLINE => {
        prev_pos = triple.2
        mbt_tokens.add_token(Invisible([0]))
      }
      _ => {
        let tok = triple.0
        let mut tok_start = triple.1
        let tok_end = triple.2
        let triple = ()
        ignore(triple)
        if is_dot_token(tok) {
          tok_start = { ..tok_start, cnum: tok_start.cnum - 1 }
        }
        if is_continuum(prev_pos, tok_start) {
          // insert Barrier
          mbt_tokens.add_token(Barrier)
        } else {
          let width = whitespace_width(prev_pos, tok_start)
          mbt_tokens.add_token(Invisible([width]))
        }
        prev_pos = tok_end
        let text = line_widths.text_of_loc(tok_start, tok_end)
        mbt_tokens.add_token(
          Visible(repr=text, kind=tok.kind(), loc=@basic.Location::{
            start: tok_start,
            end: tok_end,
          }),
        )
      }
    }
  }
  return mbt_tokens
}

///|UUID(09346902-5684-481d-9bff-1e62964a37c9)
pub fn mbttokens_to_string(tokens : ArrayView[MbtToken]) -> String {
  let buf = StringBuilder::new(size_hint=tokens.length() * 5)
  for token in tokens {
    match token {
      Visible(repr~, ..) => buf.write_iter(repr.iter())
      Invisible(repr) =>
        for width in repr {
          if width == 0 {
            buf.write_char('\n')
          } else {
            for _ in 0..<width {
              buf.write_char(' ')
            }
          }
        }
      Barrier => ()
    }
  }
  return buf.to_string()
}
