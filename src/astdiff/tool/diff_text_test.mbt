///|UUID(74905026-1f99-4aed-9889-801676fd886a)
test "diff_text renders ast-backed inline diff" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)
  let expected =
    #|--- old.mbt: line 1
    #|+++ new.mbt: line 1
    #|@@ -1,3 +1,3 @@
    #|  1 | fn f() {
    #|  2 |   foo(bar)
    #|+ 2 |   foo(baz(bar))
    #|  3 | }
    #|
  assert_true(result.kind is Ast)
  assert_true(result.rendered == expected)
}

///|UUID(fe6a815c-dfa1-4b21-af95-0ed557d4e9d6)
test "diff_text shows partial rhs highlight for wrapped call" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=DiffOptions::new(use_color=true),
  )
  assert_true(result.kind is Ast)
  assert_true(result.rendered.contains("\u{1b}[90m  2 | \u{1b}[39m  foo(bar)"))
  assert_true(
    result.rendered.contains(
      "foo(\u{1b}[32m\u{1b}[1mbaz\u{1b}[22m\u{1b}[39m(bar))",
    ),
  )
  assert_false(result.rendered.contains("\u{1b}[31m\u{1b}[1m  foo(bar)"))
}

///|UUID(7cee72fa-8f8c-4bcf-b70b-5f21305d87f2)
test "diff_text highlights only changed word inside string literal" {
  let old_source =
    #|fn f() {
    #|  println("alpha beta gamma")
    #|}
  let new_source =
    #|fn f() {
    #|  println("alpha zeta gamma")
    #|}
  let result = diff_text(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=DiffOptions::new(use_color=true),
  )
  assert_true(result.kind is Ast)
  assert_true(
    result.rendered.contains(
      "println(\"alpha \u{1b}[31m\u{1b}[1mbeta\u{1b}[22m\u{1b}[39m gamma\")",
    ),
  )
  assert_true(
    result.rendered.contains(
      "println(\"alpha \u{1b}[32m\u{1b}[1mzeta\u{1b}[22m\u{1b}[39m gamma\")",
    ),
  )
  assert_false(result.rendered.contains("\u{1b}[32m\u{1b}[1m\"alpha"))
  assert_false(result.rendered.contains("\u{1b}[31m\u{1b}[1m\"alpha"))
}

///|UUID(88eea529-4e99-40c4-9ef4-0f7083393a0f)
test "diff_text falls back to line diff on parser errors" {
  let old_source = "fn broken("
  let new_source = "fn fixed() -> Int { 1 }"
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)
  assert_true(result.kind is TextFallback(_))
  assert_true(result.rendered.has_prefix("note: fallback to line diff"))
  assert_true(result.rendered.contains("--- old.mbt"))
  assert_true(result.rendered.contains("+++ new.mbt"))
}

///|UUID(ffc583a0-bfa9-41da-b66c-454bec464d08)
test "diff_text prints each changed impl separately" {
  let old_source =
    #|fn a() {
    #|  foo(bar)
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(beta)
    #|}
  let new_source =
    #|fn a() {
    #|  foo(baz(bar))
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(gamma(beta))
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)
  let expected =
    #|--- old.mbt: line 1
    #|+++ new.mbt: line 1
    #|@@ -1,3 +1,3 @@
    #|  1 | fn a() {
    #|  2 |   foo(bar)
    #|+ 2 |   foo(baz(bar))
    #|  3 | }
    #|
    #|--- old.mbt: line 7
    #|+++ new.mbt: line 7
    #|@@ -7,3 +7,3 @@
    #|  7 | fn z() {
    #|  8 |   alpha(beta)
    #|+ 8 |   alpha(gamma(beta))
    #|  9 | }
    #|

  assert_true(result.kind is Ast)
  assert_true(result.rendered == expected)
}

///|UUID(dd5013c1-91c6-4fc3-aec3-79daed8bd382)
test "non terminate" {
  let old =
    #|pub fn decode(bytes : @bytes.View) -> String raise Malformed {
    #|  let builder = StringBuilder::new(size_hint=bytes.length())
    #|  loop bytes {
    #|    ...
    #|  }
    #|}
  let new =
    #|pub fn decode(
    #|  bytes : @bytes.View,
    #|  ignore_bom? : Bool = false,
    #|) -> String raise Malformed {
    #|  let bytes = if ignore_bom && bytes is [.. "\xef\xbb\xbf", .. rest] {
    #|    rest
    #|  } else {
    #|    bytes
    #|  }
    #|  let builder = StringBuilder::new(size_hint=bytes.length())
    #|  loop bytes {
    #|    ...
    #|  }
    #|}
  let result = diff_text(
    "old.mbt",
    old,
    "new.mbt",
    new,
    options=DiffOptions::new(use_color=true),
  )
  assert_true(result.kind is Ast)
}

///|UUID(75a63cec-04c6-4517-b902-6ee11ba6cc17)
test "diff_text keeps UUID-aligned top-level changes on the AST path" {
  let old_source =
    #|///|UUID(11111111-1111-1111-1111-111111111111)
    #|fn keep() {}
    #|///|UUID(22222222-2222-2222-2222-222222222222)
    #|fn target() {
    #|  foo(bar)
    #|}
  let new_source =
    #|///|UUID(99999999-9999-9999-9999-999999999999)
    #|fn inserted() {}
    #|///|UUID(11111111-1111-1111-1111-111111111111)
    #|fn keep() {}
    #|///|UUID(22222222-2222-2222-2222-222222222222)
    #|fn target() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.kind is Ast)
  assert_true(result.rendered.contains("--- old.mbt: line 3"))
  assert_true(result.rendered.contains("+++ new.mbt: line 5"))
  assert_true(result.rendered.contains("fn inserted() {}"))
  assert_true(result.rendered.contains("foo(bar)"))
  assert_true(result.rendered.contains("foo(baz(bar))"))
}
