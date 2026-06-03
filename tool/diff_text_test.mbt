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
    #|--- old.mbt
    #|+++ new.mbt
    #|@@ -1,3 +1,3 @@
    #|1 1 fn f() {
    #|2 .   foo(bar)
    #|. 2   foo(baz(bar))
    #|3 3 }
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
  assert_true(
    result.rendered.contains(
      "\u{1b}[90m2\u{1b}[39m \u{1b}[90m.\u{1b}[39m   foo(bar)",
    ),
  )
  assert_true(
    result.rendered.contains(
      "foo(\u{1b}[32m\u{1b}[1mbaz(\u{1b}[22m\u{1b}[39mbar\u{1b}[32m\u{1b}[1m)\u{1b}[22m\u{1b}[39m)",
    ),
  )
  assert_false(result.rendered.contains("\u{1b}[31m\u{1b}[1m  foo(bar)"))
}

///|UUID(9cc28892-f44a-44f1-a962-19fe451fe4f2)
test "diff_text colors line numbers without prefix backgrounds or separators" {
  let old_source =
    #|fn f() {
    #|  let x = 1
    #|}
  let new_source =
    #|fn f() {
    #|  let x = 2
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
      "\u{1b}[90m1\u{1b}[39m \u{1b}[90m1\u{1b}[39m fn f() {",
    ),
  )
  assert_true(
    result.rendered.contains(
      "\u{1b}[31m2\u{1b}[39m \u{1b}[90m.\u{1b}[39m   let x = ",
    ),
  )
  assert_true(
    result.rendered.contains(
      "\u{1b}[90m.\u{1b}[39m \u{1b}[32m2\u{1b}[39m   let x = ",
    ),
  )
  assert_false(result.rendered.contains("\u{1b}[100m"))
  assert_false(result.rendered.contains("\u{1b}[41m"))
  assert_false(result.rendered.contains("\u{1b}[42m"))
  assert_false(result.rendered.contains("|"))
  assert_false(result.rendered.contains("- 2"))
  assert_false(result.rendered.contains("+ 2"))
  assert_true(
    result.rendered.contains("\u{1b}[31m\u{1b}[1m1\u{1b}[22m\u{1b}[39m"),
  )
  assert_true(
    result.rendered.contains("\u{1b}[32m\u{1b}[1m2\u{1b}[22m\u{1b}[39m"),
  )
}

///|UUID(d2f6d08e-d7c4-4227-9bf5-3ee5ed6a1f2a)
test "diff_text keeps wrapped call matched when adding a sibling call" {
  let old_source =
    #|fn main() {
    #|  println(
    #|    "Hello, world!"
    #|  )
    #|}
  let new_source =
    #|fn main() {
    #|  println("Hello, world!")
    #|  println(5 + 6)
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)
  let interleaved_prefix =
    #|2 .   println(
    #|. 2   println("Hello, world!")
  let separated_suffix =
    #|4 .   )
    #|. 2   println("Hello, world!")
    #|. 3   println(5 + 6)
  assert_true(result.kind is Ast)
  assert_true(result.rendered.contains("--- old.mbt"))
  assert_true(result.rendered.contains("+++ new.mbt"))
  assert_false(result.rendered.contains("--- old.mbt: line"))
  assert_false(result.rendered.contains("+++ new.mbt: line"))
  assert_false(result.rendered.contains(interleaved_prefix))
  assert_true(result.rendered.contains(separated_suffix))
  assert_false(result.rendered.contains("-   3 |     \"Hello, world!\""))
}

///|UUID(9a02fd35-742e-448f-ae7d-88dd7cf69e8e)
test "diff_text keeps inserted case marker statements novel" {
  let old_source =
    #|fn init {
    #|  // case 002
    #|  println(fib(10))
    #|}
  let new_source =
    #|fn init {
    #|  // case 002
    #|  let marker = "case-002"
    #|  println(marker)
    #|  println(fib(8))
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.kind is Ast)
  assert_true(result.rendered.contains(". 3   let marker = \"case-002\""))
  assert_true(result.rendered.contains(". 4   println(marker)"))
  assert_true(result.rendered.contains("3 .   println(fib(10))"))
  assert_true(result.rendered.contains(". 5   println(fib(8))"))
  assert_false(result.rendered.contains("+   3   let marker = \"case-002\""))
  assert_false(result.rendered.contains("- 3 .   println(fib(10))"))
  assert_false(result.rendered.contains("3 3   let marker = \"case-002\""))
  assert_false(result.rendered.contains("3 4   println(marker)"))
}

///|UUID(1a5d3597-5a96-43ed-9e96-f88454480fd1)
test "diff_text separates mostly block replacements with one aligned line" {
  let old_source =
    #|test "debug inspect error path" {
    #|  let result = try? @debug.debug_inspect(1)
    #|  let is_err = match result {
    #|    Ok(_) => false
    #|    Err(_) => true
    #|  }
    #|  inspect(is_err, content="true")
    #| }
  let new_source =
    #|test "debug inspect error path" {
    #|  try @debug.debug_inspect(1) catch {
    #|    _ => ()
    #|  } noraise {
    #|    _ => fail("expected debug_inspect failure")
    #|  }
    #| }
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)
  let separated_block =
    #|2 .   let result = try? @debug.debug_inspect(1)
    #|3 .   let is_err = match result {
    #|4 .     Ok(_) => false
    #|5 .     Err(_) => true
    #|6 .   }
    #|7 .   inspect(is_err, content="true")
    #|. 2   try @debug.debug_inspect(1) catch {
  let interleaved_prefix =
    #|2 .   let result = try? @debug.debug_inspect(1)
    #|. 2   try @debug.debug_inspect(1) catch {

  assert_true(result.kind is Ast)
  assert_true(result.rendered.contains(separated_block))
  assert_false(result.rendered.contains(interleaved_prefix))
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

///|UUID(7c1ca837-48e4-44b3-86e5-d5ebae5c8720)
test "diff_text does not highlight unchanged trailing delimiter at line end" {
  let old_source = "let a:FixedArray[Int] = FixedArray::make(3, 2)\n"
  let new_source = "let a:FixedArray[Int] = FixedArray::make(3, 3)\n"
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
      "FixedArray::make(3, \u{1b}[31m\u{1b}[1m2\u{1b}[22m\u{1b}[39m)",
    ),
  )
  assert_true(
    result.rendered.contains(
      "FixedArray::make(3, \u{1b}[32m\u{1b}[1m3\u{1b}[22m\u{1b}[39m)",
    ),
  )
  assert_false(
    result.rendered.contains("\u{1b}[31m\u{1b}[1m2)\u{1b}[22m\u{1b}[39m"),
  )
  assert_false(
    result.rendered.contains("\u{1b}[32m\u{1b}[1m3)\u{1b}[22m\u{1b}[39m"),
  )
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
test "diff_text uses whole-file root-list diff without UUIDs" {
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
  assert_true(result.kind is Ast)
  assert_true(result.rendered.has_prefix("--- old.mbt\n+++ new.mbt\n"))
  assert_true(result.rendered.split("--- old.mbt").count() == 2)
  assert_true(result.rendered.split("+++ new.mbt").count() == 2)
  assert_false(result.rendered.contains("--- old.mbt: line"))
  assert_false(result.rendered.contains("+++ new.mbt: line"))
  assert_true(result.rendered.contains("2 .   foo(bar)"))
  assert_true(result.rendered.contains(". 2   foo(baz(bar))"))
  assert_true(result.rendered.contains("8 .   alpha(beta)"))
  assert_true(result.rendered.contains(". 8   alpha(gamma(beta))"))
  assert_true(result.rendered.contains("5 5 fn mid() {}"))
}

///|UUID(a950075e-cfce-4d10-a195-3db5d77760ed)
test "diff_text matches no-UUID top-level roots after insertion" {
  let old_source =
    #|fn keep() {}
    #|fn target() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn inserted() {}
    #|fn keep() {}
    #|fn target() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.kind is Ast)
  assert_true(result.rendered.has_prefix("--- old.mbt\n+++ new.mbt\n"))
  assert_false(result.rendered.contains("--- old.mbt: line"))
  assert_false(result.rendered.contains("+++ new.mbt: line"))
  assert_true(result.rendered.contains(". 1 fn inserted() {}"))
  assert_true(result.rendered.contains("1 2 fn keep() {}"))
  assert_true(result.rendered.contains("3 .   foo(bar)"))
  assert_true(result.rendered.contains(". 4   foo(baz(bar))"))
}

///|UUID(9a2b04b5-4a30-486c-8dc0-58806c525b56)
test "diff_text falls back to whole-file line diff for root-list graph limit" {
  let old_source =
    #|fn keep() {}
    #|fn target() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn inserted() {}
    #|fn keep() {}
    #|fn target() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=DiffOptions::new(graph_limit=0),
  )

  assert_true(result.kind is Ast)
  assert_true(
    result.rendered.has_prefix(
      "note: fallback to line diff (graph limit exceeded (0))\n--- old.mbt\n+++ new.mbt\n",
    ),
  )
  assert_false(result.rendered.contains(": line"))
  assert_true(result.rendered.contains("fn inserted() {}"))
  assert_true(result.rendered.contains("foo(baz(bar))"))
}

///|UUID(dd5013c1-91c6-4fc3-aec3-79daed8bd382)
test "non terminate" {
  let old =
    #|pub fn decode(bytes : @bytes.View) -> String raise Malformed {
    #|  let builder = StringBuilder::new(size_hint=bytes.length())
    #|  while true {
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
    #|  while true {
    #|    ...
    #|  }
    #|}
  let result = diff_text(
    "old.mbt",
    old,
    "new.mbt",
    new,
    options=DiffOptions::new(),
  )
  assert_true(result.kind is Ast)
  assert_true(
    result.rendered.contains(
      "2 10   let builder = StringBuilder::new(size_hint=bytes.length())",
    ),
  )
  assert_false(
    result.rendered.contains(
      "+   10 |   let builder = StringBuilder::new(size_hint=bytes.length())",
    ),
  )
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

///|UUID(827921ba-b988-4e71-a6cb-566e48865be0)
test "diff_text highlights inserted dot access and dot call from the dot" {
  let field_result = diff_text(
    "old.mbt",
    (
      #|fn f() {
      #|  obj
      #|}
    ),
    "new.mbt",
    (
      #|fn f() {
      #|  obj.field
      #|}
    ),
    options=DiffOptions::new(use_color=true),
  )
  assert_true(field_result.kind is Ast)
  assert_true(
    field_result.rendered.contains(
      "obj\u{1b}[32m\u{1b}[1m.field\u{1b}[22m\u{1b}[39m",
    ),
  )

  let call_result = diff_text(
    "old.mbt",
    (
      #|fn f() {
      #|  obj
      #|}
    ),
    "new.mbt",
    (
      #|fn f() {
      #|  obj.method()
      #|}
    ),
    options=DiffOptions::new(use_color=true),
  )
  assert_true(call_result.kind is Ast)
  assert_true(
    call_result.rendered.contains(
      "obj\u{1b}[32m\u{1b}[1m.method()\u{1b}[22m\u{1b}[39m",
    ),
  )
}
