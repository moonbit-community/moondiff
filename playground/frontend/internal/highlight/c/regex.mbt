///|
// Keep reusable lexical patterns separate, following moonbitlang/lexer.
const RE_NEWLINE : Regex = re"\r\n|[\r\n]"

///|
const RE_SPACE : Regex = re"[ \t\u000b\u000c\uFEFF]+"

///|
const RE_COMMENT : Regex = re"//[^\r\n]*|/\*(?:[^*]|\*+[^*/])*(?:\*+/|\**$)"

///|
const RE_UNICODE_ESCAPE : Regex = re"\\u[0-9a-fA-F]{4}|\\U[0-9a-fA-F]{8}"

///|
// Preserve the tolerant non-ASCII identifier rule. A leading BOM is trivia,
// but one inside an identifier remains part of its original spelling.
const RE_IDENTIFIER : Regex = (
    re"[a-zA-Z_\u0080-\uFEFE\uFF00-\u{10FFFF}]" | RE_UNICODE_ESCAPE
  ) +
  re"(?:[a-zA-Z0-9_\u0080-\u{10FFFF}]|\\u[0-9a-fA-F]{4}|\\U[0-9a-fA-F]{8})*"

///|
// Preprocessing numbers deliberately include incomplete literals and suffixes.
// An exponent sign follows a literal e/E/p/P, never a hex digit within a UCN
// or an identifier unit consumed after a C23 digit separator.
const RE_NUMBER : Regex = re"(?:[0-9]|\.[0-9])(?:\.|[eEpP][+\-]?|'?(?:[a-zA-Z0-9_\u0080-\u{10FFFF}]|\\u[0-9a-fA-F]{4}|\\U[0-9a-fA-F]{8}))*"

///|
const RE_ESCAPE : Regex = re"\\['\"?\\abfnrtv]|\\[0-7]{1,3}|\\x[0-9a-fA-F]+" |
  RE_UNICODE_ESCAPE

///|
const RE_HEADER : Regex = re"<[^>\r\n]*>?|\"[^\"\r\n]*\"?"

///|
const RE_OPERATOR : Regex = re">>=|<<=|\.\.\.|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||[+*/%&|\^=\-]=|::|[+*/%&|\^=<>!~?:.\-]"
