///|
// Lexical categories follow VS Code's C grammar:
// https://github.com/microsoft/vscode/blob/main/extensions/cpp/syntaxes/c.tmLanguage.json
// C23 spellings, literals and attributes follow N3096, sections 6.4 and 6.7.12:
// https://www.open-std.org/jtc1/sc22/wg14/www/docs/n3096.pdf
// No symbol table or conditional-compilation evaluation is needed for coloring.
fn word_kind(word : StringView) -> HighlightKind {
  match word {
    "break"
    | "case"
    | "continue"
    | "default"
    | "do"
    | "else"
    | "for"
    | "goto"
    | "if"
    | "return"
    | "switch"
    | "while" => Control
    "auto"
    | "const"
    | "constexpr"
    | "extern"
    | "inline"
    | "register"
    | "restrict"
    | "static"
    | "thread_local"
    | "volatile"
    | "_Atomic"
    | "_Noreturn"
    | "_Thread_local" => Modifier
    "bool"
    | "char"
    | "double"
    | "float"
    | "int"
    | "long"
    | "short"
    | "signed"
    | "unsigned"
    | "void"
    | "_BitInt"
    | "_Bool"
    | "_Complex"
    | "_Decimal32"
    | "_Decimal64"
    | "_Decimal128"
    | "_Imaginary"
    | "FILE"
    | "__builtin_va_list" => Type
    "alignas"
    | "alignof"
    | "enum"
    | "sizeof"
    | "static_assert"
    | "struct"
    | "typedef"
    | "typeof"
    | "typeof_unqual"
    | "union"
    | "_Alignas"
    | "_Alignof"
    | "_Generic"
    | "_Static_assert" => Keyword
    "_Pragma" => Control
    "true" | "false" | "TRUE" | "FALSE" | "NULL" | "nullptr" => Boolean
    "__LINE__" | "__STDC__" | "__STDC_VERSION__" | "__STDC_HOSTED__" => Number
    "__FILE__" | "__DATE__" | "__TIME__" | "__func__" => StringLiteral
    _ if word.has_suffix("_t") => Type
    _ => Variable
  }
}
