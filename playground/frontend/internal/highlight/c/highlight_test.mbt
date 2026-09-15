///|
fn colored_line(
  source : String,
  line? : Int = 1,
) -> Array[(String, @highlight.HighlightKind)] {
  let text = source.split("\n").to_array()[line - 1]
  @c.highlight(source)
  .line(line)
  .to_owned()
  .map(span => (text[span.start:span.end].to_owned(), span.kind))
}

///|
test "C declarations calls types modifiers and control flow" {
  assert_eq(
    colored_line(
      "static inline int run(const size_t n) { if (true) return call(n + 0x1fu); }",
    ),
    [
      ("static", Modifier),
      ("inline", Modifier),
      ("int", Type),
      ("run", Function),
      ("const", Modifier),
      ("size_t", Type),
      ("n", Variable),
      ("if", Control),
      ("true", Boolean),
      ("return", Control),
      ("call", Function),
      ("n", Variable),
      ("+", Operator),
      ("0x1fu", Number),
    ],
  )
  assert_eq(
    colored_line(
      "typedef struct Node { union Data *data; enum Color color; } node_t;",
    ),
    [
      ("typedef", Keyword),
      ("struct", Keyword),
      ("Node", Type),
      ("union", Keyword),
      ("Data", Type),
      ("*", Operator),
      ("data", Variable),
      ("enum", Keyword),
      ("Color", Type),
      ("color", Variable),
      ("node_t", Type),
    ],
  )
}

///|
test "keyword and type classification precedes function lookahead" {
  for
    (words, kind) in [
      (
        "break case continue default do else for goto if return switch while",
        @highlight.Control,
      ),
      (
        "auto const constexpr extern inline register restrict static thread_local volatile _Atomic _Noreturn _Thread_local",
        Modifier,
      ),
      (
        "bool char double float int long short signed unsigned void _BitInt _Bool _Complex _Decimal32 _Decimal64 _Decimal128 _Imaginary FILE uint32_t ptrdiff_t",
        Type,
      ),
      (
        "alignas alignof enum sizeof static_assert struct typedef typeof typeof_unqual union _Alignas _Alignof _Generic _Static_assert",
        Keyword,
      ),
      ("true false TRUE FALSE NULL nullptr", Boolean),
    ] {
    for word in words.split(" ") {
      assert_eq(colored_line("\{word}("), [(word.to_owned(), kind)])
    }
  }
  assert_eq(colored_line("read /* note */ (x); object.field; object->run();"), [
    ("read", Function),
    ("/* note */", Comment),
    ("x", Variable),
    ("object", Variable),
    (".", Operator),
    ("field", Variable),
    ("object", Variable),
    ("->", Operator),
    ("run", Function),
  ])
  assert_eq(colored_line("read // note\n\t()"), [
    ("read", Function),
    ("// note", Comment),
  ])
}

///|
test "C operators use complete tokens" {
  let operators = "++ -- -> << >> <= >= == != && || += -= *= /= %= &= |= ^= <<= >>= + - * / % & | ^ = < > ! ~ ? : . ... # ##"
  assert_eq(
    colored_line("x \{operators}"),
    [("x", @highlight.Variable)] +
    operators
    .split(" ")
    .to_array()
    .map(word => (word.to_owned(), @highlight.Operator)),
  )
}

///|
test "preprocessor directives headers and macro parameters" {
  assert_eq(colored_line(" \t# include /* path */ <dir//demo.h>"), [
    ("#", Control),
    ("include", Control),
    ("/* path */", Comment),
    ("<dir//demo.h>", StringLiteral),
  ])
  assert_eq(
    colored_line(
      (
        #|#include "dir\test.h"
      ),
    ),
    [("#", Control), ("include", Control), ("\"dir\\test.h\"", StringLiteral)],
  )
  assert_eq(colored_line("#define JOIN(size_t, b) size_t ## b"), [
    ("#", Control),
    ("define", Control),
    ("JOIN", Function),
    ("size_t", Variable),
    ("b", Variable),
    ("size_t", Type),
    ("##", Operator),
    ("b", Variable),
  ])
  assert_eq(colored_line("#define TEXT(x, ...) #x __VA_OPT__(,) __VA_ARGS__"), [
    ("#", Control),
    ("define", Control),
    ("TEXT", Function),
    ("x", Variable),
    ("...", Operator),
    ("#", Operator),
    ("x", Variable),
    ("__VA_OPT__", Function),
    ("__VA_ARGS__", Variable),
  ])
  assert_eq(colored_line("#define int 42"), [
    ("#", Control),
    ("define", Control),
    ("int", Function),
    ("42", Number),
  ])
  assert_eq(colored_line("#embed <data.bin>"), [
    ("#", Control),
    ("embed", Control),
    ("<data.bin>", StringLiteral),
  ])
  assert_eq(colored_line("#if __has_include /* check */ (<dir//file.h>)"), [
    ("#", Control),
    ("if", Control),
    ("__has_include", Control),
    ("/* check */", Comment),
    ("<dir//file.h>", StringLiteral),
  ])
}

///|
test "conditional branches all retain syntax and directives reset at newline" {
  let source = "#if defined(FLAG) && 0\nint disabled = 1;\n#elifdef OTHER\nint alternative = 2;\n#else\nint active = 3;\n#endif\ndefined(FLAG);"
  assert_eq(colored_line(source), [
    ("#", Control),
    ("if", Control),
    ("defined", Control),
    ("FLAG", Variable),
    ("&&", Operator),
    ("0", Number),
  ])
  for line in [2, 4, 6] {
    assert_eq(colored_line(source, line~)[0], ("int", Type))
  }
  assert_eq(colored_line(source, line=8), [
    ("defined", Function),
    ("FLAG", Variable),
  ])
  for
    directive in [
      "ifdef", "ifndef", "elif", "elifndef", "undef", "line", "pragma", "error",
      "warning",
    ] {
    assert_eq(colored_line("#\{directive} X")[1], (directive, Control))
  }
  assert_eq(colored_line("x #include <y>"), [
    ("x", Variable),
    ("#", Operator),
    ("include", Variable),
    ("<", Operator),
    ("y", Variable),
    (">", Operator),
  ])
}

///|
test "line splicing precedes identifiers comments and macro scanning" {
  let source = "#def\\\nine SUM(x) \\\n  ((x) + 1)\nint value = SU\\\nM(2); // note \\\nint hidden = 3;\n/\\\n* int hidden; *\\\n/ int visible;"
  assert_eq(colored_line(source), [("#", Control), ("def\\", Control)])
  assert_eq(colored_line(source, line=2), [
    ("ine", Control),
    ("SUM", Function),
    ("x", Variable),
  ])
  assert_eq(colored_line(source, line=3), [
    ("x", Variable),
    ("+", Operator),
    ("1", Number),
  ])
  assert_eq(colored_line(source, line=4), [
    ("int", Type),
    ("value", Variable),
    ("=", Operator),
    ("SU\\", Function),
  ])
  assert_eq(colored_line(source, line=5), [
    ("M", Function),
    ("2", Number),
    ("// note \\", Comment),
  ])
  assert_eq(colored_line(source, line=6), [("int hidden = 3;", Comment)])
  assert_eq(colored_line(source, line=7), [("/\\", Comment)])
  assert_eq(colored_line(source, line=8), [("* int hidden; *\\", Comment)])
  assert_eq(colored_line(source, line=9), [
    ("/", Comment),
    ("int", Type),
    ("visible", Variable),
  ])
}

///|
test "strings characters prefixes and C escapes" {
  assert_eq(
    colored_line(
      (
        #|u8"中文😀\a\b\f\n\r\t\v\?\'\"\\\0\12\1234\x123abc\u4e2d\U0001F600\q\o123\u{123}" L'\n' u'中' U'😀' u8'x'
      ),
    ),
    [
      ("u8\"中文😀", StringLiteral),
      ("\\a", Escape),
      ("\\b", Escape),
      ("\\f", Escape),
      ("\\n", Escape),
      ("\\r", Escape),
      ("\\t", Escape),
      ("\\v", Escape),
      ("\\?", Escape),
      ("\\'", Escape),
      ("\\\"", Escape),
      ("\\\\", Escape),
      ("\\0", Escape),
      ("\\12", Escape),
      ("\\123", Escape),
      ("4", StringLiteral),
      ("\\x123abc", Escape),
      ("\\u4e2d", Escape),
      ("\\U0001F600", Escape),
      ("\\q\\o123\\u{123}\"", StringLiteral),
      ("L'", StringLiteral),
      ("\\n", Escape),
      ("'", StringLiteral),
      ("u'中'", StringLiteral),
      ("U'😀'", StringLiteral),
      ("u8'x'", StringLiteral),
    ],
  )
  assert_eq(
    colored_line(
      (
        #|"// /* #define */" '\'' "\\n" "\x" "\u123"
      ),
    ),
    [
      ("\"// /* #define */\"", StringLiteral),
      ("'", StringLiteral),
      ("\\'", Escape),
      ("'", StringLiteral),
      ("\"", StringLiteral),
      ("\\\\", Escape),
      ("n\"", StringLiteral),
      ("\"\\x\"", StringLiteral),
      ("\"\\u123\"", StringLiteral),
    ],
  )
}

///|
test "strings splice lines while unescaped newlines recover" {
  let source = "u\\\n8\"ab\\\ncd\\n\";\n\"broken\nint next = 2;\n'bad\rint after = 3;"
  assert_eq(colored_line(source), [("u\\", StringLiteral)])
  assert_eq(colored_line(source, line=2), [("8\"ab\\", StringLiteral)])
  assert_eq(colored_line(source, line=3), [
    ("cd", StringLiteral),
    ("\\n", Escape),
    ("\"", StringLiteral),
  ])
  assert_eq(colored_line(source, line=4), [("\"broken", StringLiteral)])
  assert_eq(colored_line(source, line=5), [
    ("int", Type),
    ("next", Variable),
    ("=", Operator),
    ("2", Number),
  ])
  assert_eq(@c.highlight(source).line(7)[0].kind, Type)
}

///|
test "comments hide fake code and incomplete block comments reach EOF" {
  let source = "/* if (false) {\n #define FAKE \"string\"\n */ int real; // foo()\n/* unterminated\nint hidden;"
  assert_eq(colored_line(source), [("/* if (false) {", Comment)])
  assert_eq(colored_line(source, line=2), [
    (" #define FAKE \"string\"", Comment),
  ])
  assert_eq(colored_line(source, line=3), [
    (" */", Comment),
    ("int", Type),
    ("real", Variable),
    ("// foo()", Comment),
  ])
  assert_eq(colored_line(source, line=5), [("int hidden;", Comment)])
  assert_eq(colored_line("/* first */ #define VALUE 1"), [
    ("/* first */", Comment),
    ("#", Control),
    ("define", Control),
    ("VALUE", Function),
    ("1", Number),
  ])
}

///|
test "numeric bases exponents suffixes and C23 digit separators" {
  for
    number in [
      "0", "0777UL", "123llu", "0xffU", "0XABCDLL", "1.5", ".5f", "1.", "1e-9L",
      "2E+3", "0x1.fp+2", "0X.8P-1F", "0b1010", "0B11'00u", "1'000'000", "0xFF'AB",
      "1'2.3'4e5'6", "42wb", "42UWB", "1.0df", "2.0DD", "3.0dl",
    ] {
    assert_eq(colored_line(number), [(number, Number)])
  }
  assert_eq(colored_line("a-1 + 2*3 / 4; . member"), [
    ("a", Variable),
    ("-", Operator),
    ("1", Number),
    ("+", Operator),
    ("2", Number),
    ("*", Operator),
    ("3", Number),
    ("/", Operator),
    ("4", Number),
    (".", Operator),
    ("member", Variable),
  ])
}

///|
test "C23 attributes preserve tags strings and balanced arguments" {
  assert_eq(
    colored_line(
      "struct [[deprecated(\"old\")]] Node; [[vendor::attr((x), [y]), nodiscard]] int run();",
    ),
    [
      ("struct", Keyword),
      ("[[", Attribute),
      ("deprecated", Attribute),
      ("\"old\"", StringLiteral),
      ("]]", Attribute),
      ("Node", Type),
      ("[[", Attribute),
      ("vendor", Attribute),
      ("::", Operator),
      ("attr", Attribute),
      ("x", AttributeParameter),
      ("y", AttributeParameter),
      ("nodiscard", Attribute),
      ("]]", Attribute),
      ("int", Type),
      ("run", Function),
    ],
  )
  assert_eq(colored_line("[[maybe_unused; int restored;"), [
    ("[[", Attribute),
    ("maybe_unused", Attribute),
    ("int", Type),
    ("restored", Variable),
  ])
  assert_eq(
    colored_line("struct [ /* tag */ [deprecated(42)] /* end */ ] Node;"),
    [
      ("struct", Keyword),
      ("[", Attribute),
      ("/* tag */", Comment),
      ("[", Attribute),
      ("deprecated", Attribute),
      ("42", Number),
      ("]", Attribute),
      ("/* end */", Comment),
      ("]", Attribute),
      ("Node", Type),
    ],
  )
}
