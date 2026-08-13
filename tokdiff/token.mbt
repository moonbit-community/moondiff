// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// The weight class of a token. Weights encode semantic importance for the
/// alignment scorer: identifiers and literals carry full signal, punctuation
/// less, comment content little, and comment boilerplate / whitespace none to
/// almost none.
pub(all) enum TokKind {
  Word // identifiers, keywords, numbers
  Str // string / char / bytes / regex literals (one token each)
  Punct // operators, brackets, separators
  Comment // content tokens inside a comment (tokenized, never opaque)
  Filler // comment boilerplate: `//` markers and comment whitespace
  Space // inter-token whitespace (reconstructed from lexer position gaps)
  Marker // the `///|` block separator (full weight: structural, not prose)
} derive(Eq)

///|
/// One diffable token: its weight class and its exact source text.
/// Concatenating the `text` of `tokenize_line`'s result reproduces the line.
pub struct Tok {
  kind : TokKind
  text : String
}

///|
pub fn Tok::kind(self : Tok) -> TokKind {
  self.kind
}

///|
pub fn Tok::text(self : Tok) -> String {
  self.text
}

///|
/// The baseline alignment weight of a token class (integer; all scoring is
/// integer so results are bit-identical on every backend). Token-level
/// refinements such as comma downweighting are applied by the internal scorer.
fn TokKind::weight(self : TokKind) -> Int {
  match self {
    Word | Str | Marker => 20
    Punct => 6
    Comment => 2
    Space => 1
    Filler => 0
  }
}

///|
/// Token-level weight used by semantic alignment. A comma is mostly a list
/// separator and is frequently introduced mechanically when formatting a
/// construct across multiple lines, so it carries only the smallest non-zero
/// amount of evidence. Other punctuation keeps the structural `Punct` weight.
fn alignment_weight(token : Tok) -> Int {
  if token.kind is Punct && token.text == "," {
    1
  } else {
    token.kind.weight()
  }
}

///|
/// Tokenize the inside of a comment: words keep a little weight so similar
/// comments pair (and identical comments win ties), while the `//` markers
/// and comment spacing are weightless `Filler` — shared boilerplate must not
/// make unrelated comments look similar.
fn push_comment_tokens(toks : Array[Tok], body : String) -> Unit {
  let mut rest = body.view()
  while rest is [_, ..] {
    rest = lexmatch rest with longest {
      (re"^//+" as t, after=next) => {
        toks.push({ kind: Filler, text: t.to_owned() })
        next
      }
      (re"^[ \t]+" as t, after=next) => {
        toks.push({ kind: Filler, text: t.to_owned() })
        next
      }
      (re"^[A-Za-z0-9_]+" as t, after=next) => {
        toks.push({ kind: Comment, text: t.to_owned() })
        next
      }
      (re"^." as t, after=next) => {
        toks.push({ kind: Comment, text: t.to_string() })
        next
      }
      _ => abort("unreachable")
    }
  }
}

///|
/// The upstream lexer advances recursively once per lexical item. Keep a
/// conservative, backend-independent ceiling below the JavaScript/Wasm stack
/// limit and switch to the iterative tokenizer below before invoking it.
const LEXER_COMPLEXITY_LIMIT : Int = 256

///|
fn fallback_char_class(c : Char) -> Int {
  if c.is_whitespace() {
    0
  } else if c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    c == '_' ||
    !c.is_ascii() {
    1
  } else {
    2
  }
}

///|
fn starts_line_comment(line : String, offset : Int) -> Bool {
  line.get_char(offset) == Some('/') && line.get_char(offset + 1) == Some('/')
}

///|
fn starts_marker(line : String, offset : Int) -> Bool {
  starts_line_comment(line, offset) &&
  line.get_char(offset + 2) == Some('/') &&
  line.get_char(offset + 3) == Some('|')
}

///|
/// Estimate the number of recursive lexer advances without calling the
/// lexer. Runs of identifier and whitespace characters count once;
/// punctuation counts individually. The scan intentionally does not try to
/// recognize comments or quoted literals: treating `//` inside a string as a
/// comment would underestimate an interpolation-heavy line, while a
/// conservative overestimate only selects the lossless fallback sooner.
fn lexer_complexity_within_limit(line : String) -> Bool {
  let mut offset = 0
  let mut pieces = 0
  while offset < line.length() {
    guard line.get_char(offset) is Some(c) else { break }
    let cls = fallback_char_class(c)
    pieces += 1
    if pieces > LEXER_COMPLEXITY_LIMIT {
      return false
    }
    offset += c.utf16_len()
    if cls != 2 {
      while line.get_char(offset) is Some(next) &&
            fallback_char_class(next) == cls {
        offset += next.utf16_len()
      }
    }
  }
  true
}

///|
/// Iterative equivalent of comment tokenization used by the long-line
/// fallback. It deliberately mirrors `push_comment_tokens`: slash markers
/// and whitespace are filler, ASCII word runs are comment content, and every
/// other Unicode character is one lossless content token.
fn push_fallback_comment_tokens(
  toks : Array[Tok],
  line : String,
  start : Int,
) -> Unit {
  let mut offset = start
  while offset < line.length() {
    guard line.get_char(offset) is Some(c) else { break }
    let token_start = offset
    let kind = if c == '/' {
      while line.get_char(offset) == Some('/') {
        offset += 1
      }
      Filler
    } else if c == ' ' || c == '\t' {
      while line.get_char(offset) is Some(' ' | '\t') {
        offset += 1
      }
      Filler
    } else if c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' {
      while line.get_char(offset) is Some(next) &&
            (next.is_ascii_alphabetic() || next.is_ascii_digit() || next == '_') {
        offset += next.utf16_len()
      }
      Comment
    } else {
      offset += c.utf16_len()
      Comment
    }
    toks.push({
      kind,
      text: line.view(start_offset=token_start, end_offset=offset).to_owned(),
    })
  }
}

///|
/// Lossless, non-recursive tokenization for externally supplied lines whose
/// estimated lexical depth is unsafe for the real lexer. This is only a
/// safety fallback: it keeps broad language-aware classes so the existing
/// token-count and DP budgets can make the final degradation decision.
fn fallback_tokenize_line(line : String) -> Array[Tok] {
  let toks : Array[Tok] = []
  let mut offset = 0
  while offset < line.length() {
    if starts_line_comment(line, offset) {
      if starts_marker(line, offset) {
        toks.push({ kind: Marker, text: "///|" })
        push_fallback_comment_tokens(toks, line, offset + 4)
      } else {
        push_fallback_comment_tokens(toks, line, offset)
      }
      break
    }
    guard line.get_char(offset) is Some(c) else { break }
    let token_start = offset
    let cls = fallback_char_class(c)
    offset += c.utf16_len()
    if cls != 2 {
      while line.get_char(offset) is Some(next) &&
            fallback_char_class(next) == cls {
        offset += next.utf16_len()
      }
    }
    toks.push({
      kind: match cls {
        0 => Space
        1 => Word
        _ => Punct
      },
      text: line.view(start_offset=token_start, end_offset=offset).to_owned(),
    })
  }
  toks
}

///|
fn classify(tok : @tokens.Token, text : String) -> TokKind {
  match tok {
    CHAR(_)
    | BYTE(_)
    | BYTES(_)
    | STRING(_)
    | MULTILINE_STRING(_)
    | MULTILINE_INTERP(_)
    | INTERP(_)
    | REGEX_LITERAL(_)
    | REGEX_INTERP(_) => Str
    // identifier-like tokens are Word regardless of spelling (Unicode
    // identifiers must not fall through to Punct), and attributes /
    // package references carry identifier-grade signal
    LIDENT(_)
    | UIDENT(_)
    | POST_LABEL(_)
    | DOT_LIDENT(_)
    | DOT_UIDENT(_)
    | PACKAGE_NAME(_)
    | ATTRIBUTE(_)
    | INT(_)
    | FLOAT(_)
    | DOUBLE(_) => Word
    _ =>
      match text {
        [c, ..] if (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          c == '_' ||
          (c >= '0' && c <= '9') => Word
        _ => Punct
      }
  }
}

///|
/// Tokenize one line of MoonBit source with the real MoonBit lexer
/// (`moonbitlang/lexer`), mapping language tokens to weight classes:
///
/// - identifiers / keywords / numbers -> `Word`
/// - string, char, bytes and regex literals -> `Str` (one token each)
/// - operators and separators -> `Punct`
/// - comments -> content-tokenized `Comment` words + weightless `Filler`
/// - gaps between token spans (whitespace the lexer skipped) -> `Space`,
///   reconstructed from positions so concatenation reproduces the line
///
/// Lexical errors are ignored (diffs are routinely taken of incomplete
/// code); the lexer's best-effort token stream is used as is.
pub fn tokenize_line(line : String) -> Array[Tok] {
  if !lexer_complexity_within_limit(line) {
    return fallback_tokenize_line(line)
  }
  let toks : Array[Tok] = []
  let r = @lexer.tokens_from_string_with_utf16_location(comment=true, line)
  let mut prev_end = 0
  for triple in r.tokens {
    let (tok, sp, ep) = triple
    if tok is (NEWLINE | EOF) {
      continue
    }
    if sp.cnum > prev_end {
      toks.push({
        kind: Space,
        text: line.view(start_offset=prev_end, end_offset=sp.cnum).to_owned(),
      })
    }
    let text = line.view(start_offset=sp.cnum, end_offset=ep.cnum).to_owned()
    match tok {
      COMMENT(_) =>
        if text is ['/', '/', '/', '|', ..] {
          toks.push({ kind: Marker, text: "///|" })
          push_comment_tokens(toks, text.view(start_offset=4).to_owned())
        } else {
          push_comment_tokens(toks, text)
        }
      _ => toks.push({ kind: classify(tok, text), text })
    }
    prev_end = ep.cnum
  }
  if prev_end < line.length() {
    toks.push({ kind: Space, text: line.view(start_offset=prev_end).to_owned() })
  }
  toks
}
