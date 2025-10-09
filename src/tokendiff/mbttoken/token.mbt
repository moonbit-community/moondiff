///|
pub(all) enum MbtToken {
  Visible(
    kind~ : @tokens.TokenKind,
    loc~ : @basic.Location,
    repr~ : Array[Char]
  )
  Invisible(Array[Char])
  Barrier
}

///|
pub impl Show for MbtToken with output(self, logger) {
  match self {
    Visible(kind~, loc~, repr~) => {
      logger.write_string("Visible(")
      logger.write_string(kind.to_string())
      logger.write_string(", ")
      logger.write_string(loc.to_string())
      logger.write_string(", \"")
      logger.write_string(String::from_iter(repr.iter()).escape())
      logger.write_string("\")")
    }
    Invisible(repr) => {
      logger.write_string("Invisible(\"")
      logger.write_string(String::from_iter(repr.iter()).escape())
      logger.write_string("\")")
    }
    Barrier => logger.write_string("Barrier")
  }
}

///|
pub impl ToJson for MbtToken with to_json(self) {
  match self {
    Invisible(text) => String::from_array(text).to_json()
    Visible(kind~, repr~, ..) =>
      { "kind": kind.to_string(), "repr": String::from_array(repr) }
    Barrier => "<|Barrier|>"
  }
}

///|
pub fn MbtToken::to_text(self : MbtToken) -> Array[Char] {
  match self {
    Visible(repr~, ..) | Invisible(repr) => repr
    Barrier => []
  }
}

///|
pub fn MbtToken::get_unicodes(self : MbtToken) -> Array[Char] {
  match self {
    Visible(repr~, ..) | Invisible(repr) => repr
    Barrier => []
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
  if token is Invisible(s) {
    if self is [.., last] && last is Invisible(prev_s) {
      self[self.length() - 1] = Invisible(prev_s + s)
    } else {
      self.push(token)
    }
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
    lnum: -1,
    fname: "dummy",
    bol: -1,
    cnum: -1,
  }
  for triple in triples {
    match triple.0 {
      EOF => break
      SEMI(false) => continue
      NEWLINE => {
        prev_pos = triple.2
        mbt_tokens.add_token(Invisible(['\n']))
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
        if prev_pos.lnum != -1 {
          if is_continuum(prev_pos, tok_start) {
            // insert Barrier
            mbt_tokens.add_token(Barrier)
          } else {
            let width = whitespace_width(prev_pos, tok_start)
            mbt_tokens.add_token(Invisible(Array::make(width, ' ')))
          }
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
      Visible(repr~, ..) | Invisible(repr) => buf.write_iter(repr.iter())
      Barrier => ()
    }
  }
  return buf.to_string()
}
