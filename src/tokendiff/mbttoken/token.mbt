///|
pub(all) enum MbtToken {
  Visible(
    kind~ : @tokens.TokenKind,
    loc~ : @basic.Location,
    repr~ : Array[Char]
  )
  Invisible(Array[Int]) // whitespace widths, 0 for newline
  Barrier
}

///|
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

///|
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

///|
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

///|
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

///|
fn is_continuum(prev : @basic.Position, next : @basic.Position) -> Bool {
  (prev.lnum == next.lnum && prev.column() == next.column()) ||
  (prev.lnum + 1 == next.lnum && next.column() == 1)
}

///|
fn whitespace_width(prev : @basic.Position, next : @basic.Position) -> Int {
  if prev.lnum == next.lnum {
    next.column() - prev.column()
  } else {
    next.column() - 1
  }
}

///|
fn is_dot_token(token : @tokens.Token) -> Bool {
  token is DOT_INT(_) ||
  token is DOT_LIDENT(_) ||
  token is DOT_LPAREN ||
  token is DOT_UIDENT(_)
}

///|
fn Array::add_token(self : Array[MbtToken], token : MbtToken) -> Unit {
  if token is Invisible([w]) && self is [.., last] && last is Invisible(widths) {
    widths.push(w)
  } else {
    self.push(token)
  }
}

///|
pub fn MbtToken::from_triples(
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

///|
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
