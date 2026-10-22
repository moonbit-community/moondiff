///|
priv enum Punctuation {
  OpenParen
  CloseParen
  OpenBracket
  CloseBracket
  OpenBrace
  CloseBrace
  Semicolon
  Hash
  HashHash
  Operator
  Other
} derive(Eq)

///|
/// Return the token's meaning and the remaining source. Delimiters have
/// the same scope regardless of spelling; strings, headers and comments are
/// consumed separately before this classification can affect lexical state.
fn punctuation_at(input : StringView) -> (Punctuation, StringView) {
  lexmatch input with longest {
    (re"^\(", after=rest) => (OpenParen, rest)
    (re"^\)", after=rest) => (CloseParen, rest)
    (re"^(?:\[|<:)", after=rest) => (OpenBracket, rest)
    (re"^(?:\]|:>)", after=rest) => (CloseBracket, rest)
    (re"^(?:[{]|<%)", after=rest) => (OpenBrace, rest)
    (re"^(?:[}]|%>)", after=rest) => (CloseBrace, rest)
    (re"^;", after=rest) => (Semicolon, rest)
    (re"^(?:#|%:)", after=rest) => (Hash, rest)
    (re"^(?:##|%:%:)", after=rest) => (HashHash, rest)
    (re"^" + RE_OPERATOR, after=rest) => (Operator, rest)
    (re"^[\u0000-\u{10FFFF}]", after=rest) => (Other, rest)
    re"^$" => (Other, input)
  }
}

///|
fn next_token(input : StringView, stop_at_newline~ : Bool) -> StringView {
  for input = input {
    lexmatch input with longest {
      (re"^" + RE_SPACE, after=rest) => continue rest
      (re"^" + RE_COMMENT, after=rest) => continue rest
      (re"^" + RE_NEWLINE, after=rest) =>
        if stop_at_newline {
          break input[input.length():]
        } else {
          continue rest
        }
      _ => break input
    }
  }
}

///|
fn followed_by_paren(input : StringView, stop_at_newline~ : Bool) -> Bool {
  let next = next_token(input, stop_at_newline~)
  punctuation_at(next).0 is OpenParen
}
