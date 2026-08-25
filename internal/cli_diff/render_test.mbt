///|UUID(74905026-1f99-4aed-9889-801676fd886a)
test "render renders CST-backed inline diff" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = render("old.mbt", old_source, "new.mbt", new_source)
  let expected =
    #|--- old.mbt: line 1
    #|+++ new.mbt: line 1
    #|@@ -1,3 +1,3 @@
    #|1 1 fn f() {
    #|2 .   foo(bar)
    #|. 2   foo(baz(bar))
    #|3 3 }
    #|
  assert_true(result == expected)
}

///|
test "render renders structural changes with negative context as zero" {
  let old_source =
    #|fn f() {
    #|  let value = 1
    #|}
  let new_source =
    #|fn f() {
    #|  let value = 2
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(context_lines=-2),
  )
  assert_true(result.contains("let value = 1"))
  assert_true(result.contains("let value = 2"))
}

///|
test "render ignores Unicode whitespace-only changes structurally" {
  let old_source = "let value = 1\n"
  for unicode_space in ["\u{00a0}", "\u{3000}"] {
    let new_source = "let\{unicode_space}value = 1\n"
    let result = render("old.mbt", old_source, "new.mbt", new_source)
    assert_eq(result, "")
  }
}

///|
test "render returns before parsing identical sources" {
  let source = "fn broken("
  let result = render("old.mbt", source, "new.mbt", source)
  assert_eq(result, "--- old.mbt\n+++ new.mbt\nNo changes.\n")
}

///|UUID(31d25c5a-0e2a-49e8-9e32-8de8940bded3)
test "render colors file headers blue" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(use_color=true),
  )
  assert_true(
    result.has_prefix(
      "\u{1b}[34m--- old.mbt: line 1\u{1b}[39m\n\u{1b}[34m+++ new.mbt: line 1\u{1b}[39m\n",
    ),
  )
}

///|UUID(fe6a815c-dfa1-4b21-af95-0ed557d4e9d6)
test "render shows partial rhs highlight for wrapped call" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(use_color=true),
  )
  assert_true(
    result.contains(
      "\u{1b}[90m2\u{1b}[39m \u{1b}[90m.\u{1b}[39m \u{1b}[90m  foo(bar)\u{1b}[39m",
    ),
  )
  assert_true(
    result.contains(
      "\u{1b}[90m  foo(\u{1b}[39m\u{1b}[32m\u{1b}[1mbaz(\u{1b}[22m\u{1b}[39m\u{1b}[90mbar\u{1b}[39m\u{1b}[32m\u{1b}[1m)\u{1b}[22m\u{1b}[39m",
    ),
  )
  assert_false(result.contains("\u{1b}[31m\u{1b}[1m  foo(bar)"))
}

///|UUID(9cc28892-f44a-44f1-a962-19fe451fe4f2)
test "render colors line numbers without prefix backgrounds or separators" {
  let old_source =
    #|fn f() {
    #|  let x = 1
    #|}
  let new_source =
    #|fn f() {
    #|  let x = 2
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(use_color=true),
  )

  assert_true(
    result.contains("\u{1b}[90m1\u{1b}[39m \u{1b}[90m1\u{1b}[39m fn f() {"),
  )
  assert_false(
    result.contains(
      "\u{1b}[90m1\u{1b}[39m \u{1b}[90m1\u{1b}[39m \u{1b}[90mfn f() {\u{1b}[39m",
    ),
  )
  assert_true(
    result.contains(
      "\u{1b}[31m2\u{1b}[39m \u{1b}[90m.\u{1b}[39m \u{1b}[90m  let x = \u{1b}[39m",
    ),
  )
  assert_true(
    result.contains(
      "\u{1b}[90m.\u{1b}[39m \u{1b}[32m2\u{1b}[39m \u{1b}[90m  let x = \u{1b}[39m",
    ),
  )
  assert_false(result.contains("\u{1b}[100m"))
  assert_false(result.contains("\u{1b}[41m"))
  assert_false(result.contains("\u{1b}[42m"))
  assert_false(result.contains("|"))
  assert_false(result.contains("- 2"))
  assert_false(result.contains("+ 2"))
  assert_true(result.contains("\u{1b}[31m\u{1b}[1m1\u{1b}[22m\u{1b}[39m"))
  assert_true(result.contains("\u{1b}[32m\u{1b}[1m2\u{1b}[22m\u{1b}[39m"))
}

///|UUID(d2f6d08e-d7c4-4227-9bf5-3ee5ed6a1f2a)
test "render keeps wrapped call matched when adding a sibling call" {
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)
  let interleaved_prefix =
    #|2 .   println(
    #|. 2   println("Hello, world!")
  let separated_suffix =
    #|4 .   )
    #|. 2   println("Hello, world!")
    #|. 3   println(5 + 6)
  assert_true(result.contains("--- old.mbt"))
  assert_true(result.contains("+++ new.mbt"))
  assert_true(result.contains("--- old.mbt: line 1"))
  assert_true(result.contains("+++ new.mbt: line 1"))
  assert_false(result.contains(interleaved_prefix))
  assert_true(result.contains(separated_suffix))
  assert_false(result.contains("-   3 |     \"Hello, world!\""))
}

///|UUID(9a02fd35-742e-448f-ae7d-88dd7cf69e8e)
test "render keeps inserted case marker statements novel" {
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.contains(". 3   let marker = \"case-002\""))
  assert_true(result.contains(". 4   println(marker)"))
  assert_true(result.contains("3 .   println(fib(10))"))
  assert_true(result.contains(". 5   println(fib(8))"))
  assert_false(result.contains("+   3   let marker = \"case-002\""))
  assert_false(result.contains("- 3 .   println(fib(10))"))
  assert_false(result.contains("3 3   let marker = \"case-002\""))
  assert_false(result.contains("3 4   println(marker)"))
}

///|UUID(1a5d3597-5a96-43ed-9e96-f88454480fd1)
test "render separates mostly block replacements with one aligned line" {
  let old_source =
    #|test "debug inspect error path" {
    #|  let result = try! @debug.debug_inspect(1)
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)
  let separated_block =
    #|2 .   let result = try! @debug.debug_inspect(1)
    #|3 .   let is_err = match result {
    #|4 .     Ok(_) => false
    #|5 .     Err(_) => true
    #|6 .   }
    #|7 .   inspect(is_err, content="true")
    #|. 2   try @debug.debug_inspect(1) catch {
  let interleaved_prefix =
    #|2 .   let result = try! @debug.debug_inspect(1)
    #|. 2   try @debug.debug_inspect(1) catch {

  assert_true(result.contains(separated_block))
  assert_false(result.contains(interleaved_prefix))
}

///|UUID(7cee72fa-8f8c-4bcf-b70b-5f21305d87f2)
test "render highlights only changed word inside string literal" {
  let old_source =
    #|fn f() {
    #|  println("alpha beta gamma")
    #|}
  let new_source =
    #|fn f() {
    #|  println("alpha zeta gamma")
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(use_color=true),
  )
  assert_true(
    result.contains(
      "\u{1b}[90m  println(\"alpha \u{1b}[39m\u{1b}[31m\u{1b}[1mbeta\u{1b}[22m\u{1b}[39m\u{1b}[90m gamma\")\u{1b}[39m",
    ),
  )
  assert_true(
    result.contains(
      "\u{1b}[90m  println(\"alpha \u{1b}[39m\u{1b}[32m\u{1b}[1mzeta\u{1b}[22m\u{1b}[39m\u{1b}[90m gamma\")\u{1b}[39m",
    ),
  )
  assert_false(result.contains("\u{1b}[32m\u{1b}[1m\"alpha"))
  assert_false(result.contains("\u{1b}[31m\u{1b}[1m\"alpha"))
}

///|UUID(7c1ca837-48e4-44b3-86e5-d5ebae5c8720)
test "render does not highlight unchanged trailing delimiter at line end" {
  let old_source = "let a:FixedArray[Int] = FixedArray::make(3, 2)\n"
  let new_source = "let a:FixedArray[Int] = FixedArray::make(3, 3)\n"
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(use_color=true),
  )
  assert_true(
    result.contains(
      "\u{1b}[90mlet a:FixedArray[Int] = FixedArray::make(3, \u{1b}[39m\u{1b}[31m\u{1b}[1m2\u{1b}[22m\u{1b}[39m\u{1b}[90m)\u{1b}[39m",
    ),
  )
  assert_true(
    result.contains(
      "\u{1b}[90mlet a:FixedArray[Int] = FixedArray::make(3, \u{1b}[39m\u{1b}[32m\u{1b}[1m3\u{1b}[22m\u{1b}[39m\u{1b}[90m)\u{1b}[39m",
    ),
  )
  assert_false(result.contains("\u{1b}[31m\u{1b}[1m2)\u{1b}[22m\u{1b}[39m"))
  assert_false(result.contains("\u{1b}[32m\u{1b}[1m3)\u{1b}[22m\u{1b}[39m"))
}

///|UUID(88eea529-4e99-40c4-9ef4-0f7083393a0f)
test "render falls back to tokdiff on parser errors" {
  let old_source = "fn broken("
  let new_source = "fn fixed() -> Int { 1 }"
  let result = render("old.mbt", old_source, "new.mbt", new_source)
  assert_true(result.has_prefix("note: fallback to tokdiff"))
  assert_true(result.contains("--- old.mbt"))
  assert_true(result.contains("+++ new.mbt"))
}

///|UUID(ffc583a0-bfa9-41da-b66c-454bec464d08)
test "render uses per-top-level diff without UUIDs" {
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)
  assert_true(result.contains("--- old.mbt: line 1"))
  assert_true(result.contains("+++ new.mbt: line 1"))
  assert_true(result.contains("--- old.mbt: line 7"))
  assert_true(result.contains("+++ new.mbt: line 7"))
  assert_true(result.split("--- old.mbt: line").count() == 3)
  assert_true(result.split("+++ new.mbt: line").count() == 3)
  assert_true(result.contains("2 .   foo(bar)"))
  assert_true(result.contains(". 2   foo(baz(bar))"))
  assert_true(result.contains("8 .   alpha(beta)"))
  assert_true(result.contains(". 8   alpha(gamma(beta))"))
  assert_false(result.contains("5 5 fn mid() {}"))
}

///|UUID(a950075e-cfce-4d10-a195-3db5d77760ed)
test "render matches no-UUID top-level roots after insertion" {
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.contains("--- old.mbt: line 2"))
  assert_true(result.contains("+++ new.mbt: line 3"))
  assert_true(result.contains("--- old.mbt\n+++ new.mbt: line 1"))
  assert_false(result.contains("--- old.mbt\n+++ new.mbt\n"))
  assert_true(result.contains(". 1 fn inserted() {}"))
  assert_false(result.contains("1 2 fn keep() {}"))
  assert_true(result.contains("3 .   foo(bar)"))
  assert_true(result.contains(". 4   foo(baz(bar))"))
}

///|UUID(9a2b04b5-4a30-486c-8dc0-58806c525b56)
test "render falls back to single-definition tokdiff for graph limit" {
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
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(graph_limit=0),
  )

  assert_true(
    result.has_prefix(
      "note: fallback to tokdiff (graph limit exceeded (0) at old line 2, new line 3)\n--- old.mbt: line 2\n+++ new.mbt: line 3\n",
    ),
  )
  assert_true(result.contains("--- old.mbt\n+++ new.mbt: line 1"))
  assert_true(result.contains("fn inserted() {}"))
  assert_true(result.contains("foo(baz(bar))"))
}

///|
test "render uses whole-document tokdiff for root graph limit" {
  let result = render(
    "old.mbt",
    "test {\n  inspect(old_value)\n}",
    "new.mbt",
    "test {\n  inspect(new_value)\n}",
    options=Options::new(graph_limit=0),
  )
  assert_true(
    result.has_prefix(
      "note: fallback to tokdiff (graph limit exceeded (0))\n--- old.mbt\n+++ new.mbt\n",
    ),
  )
  assert_true(result.contains("2 .   inspect(old_value)"))
  assert_true(result.contains(". 2   inspect(new_value)"))
}

///|
test "render reports pure comment changes as empty when ignored" {
  let old_source =
    #|/// old docs
    #|fn value() -> Int { 1 } // old trailing
  let new_source =
    #|/// new docs
    #|fn value() -> Int { 1 } // new trailing
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(ignore_comments=true),
  )
  assert_eq(
    result, "--- old.mbt\n+++ new.mbt\nNo changes besides comments or blank lines.\n",
  )
}

///|
test "render reports blank-line and final-newline changes as empty when ignored" {
  let result = render(
    "old.mbt",
    "fn stable() -> Int { 1 }",
    "new.mbt",
    "fn stable() -> Int { 1 }\n\n\t\n\u{2003}",
    options=Options::new(ignore_comments=true),
  )
  assert_eq(
    result, "--- old.mbt\n+++ new.mbt\nNo changes besides comments or blank lines.\n",
  )
}

///|
test "parser fallback reports ignored blank-line changes with the shared empty state" {
  let result = render(
    "old.mbt",
    "fn broken( {\n",
    "new.mbt",
    "fn broken( {\n\u{3000}\n",
    options=Options::new(ignore_comments=true),
  )
  assert_eq(
    result, "--- old.mbt\n+++ new.mbt\nNo changes besides comments or blank lines.\n",
  )
}

///|
test "render keeps ignored comments neutral around code changes" {
  let old_source =
    #|/// old docs
    #|fn value() -> Int {
    #|  old_value() // old explanation
    #|}
  let new_source =
    #|/// new docs
    #|fn value() -> Int {
    #|  new_value()  // new explanation
    #|}
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(ignore_comments=true, use_color=true),
  )
  assert_true(result.contains("old docs"), msg=result)
  assert_true(result.contains("new docs"), msg=result)
  assert_true(result.contains("old explanation"), msg=result)
  assert_true(result.contains("new explanation"), msg=result)
  assert_true(
    result.contains("\u{1b}[31m\u{1b}[1mold_value\u{1b}[22m\u{1b}[39m"),
    msg=result,
  )
  assert_true(
    result.contains("\u{1b}[32m\u{1b}[1mnew_value\u{1b}[22m\u{1b}[39m"),
    msg=result,
  )
  assert_false(
    result.contains("\u{1b}[31m\u{1b}[1mold explanation"),
    msg=result,
  )
  assert_false(
    result.contains("\u{1b}[32m\u{1b}[1mnew explanation"),
    msg=result,
  )
}

///|
test "render does not treat slashes inside strings as comments" {
  let result = render(
    "old.mbt",
    "fn url() -> String { \"https://old.example/a//b\" }",
    "new.mbt",
    "fn url() -> String { \"https://new.example/a//b\" }",
    options=Options::new(ignore_comments=true),
  )
  assert_false(result.contains("No changes besides comments or blank lines."))
  assert_true(result.contains("https://old.example/a//b"))
  assert_true(result.contains("https://new.example/a//b"))
}

///|
test "render ignores UUID and block separator comment changes" {
  let old_source =
    #|///|UUID(old-id)
    #|fn value() -> Int { 1 }
  let new_source =
    #|///|
    #|///|UUID(new-id)
    #|fn value() -> Int { 1 }
  let result = render(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=Options::new(ignore_comments=true),
  )
  assert_true(result.contains("No changes besides comments or blank lines."))
}

///|
test "parser fallback applies comment filtering in tokdiff" {
  let result = render(
    "old.mbt",
    "fn broken( { old_value // old comment",
    "new.mbt",
    "fn broken( { new_value // new comment",
    options=Options::new(ignore_comments=true, use_color=true),
  )
  assert_true(result.has_prefix("note: fallback to tokdiff"))
  assert_true(result.contains("old comment"), msg=result)
  assert_true(result.contains("new comment"), msg=result)
  assert_false(result.contains("\u{1b}[31m\u{1b}[1mold comment"), msg=result)
  assert_false(result.contains("\u{1b}[32m\u{1b}[1mnew comment"), msg=result)
}

///|UUID(3b45c1da-9379-4be0-a59c-75f685ff3dce)
test "render keeps whole-file root-list diff when unkeyed top-level items cannot be paired" {
  let old_source =
    #|test {
    #|  inspect(1)
    #|}
  let new_source =
    #|test {
    #|  inspect(2)
    #|}
  let result = render("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.has_prefix("--- old.mbt\n+++ new.mbt\n"))
  assert_false(result.contains(": line"))
  assert_true(result.contains("2 .   inspect(1)"))
  assert_true(result.contains(". 2   inspect(2)"))
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
  let result = render("old.mbt", old, "new.mbt", new, options=Options::new())
  assert_true(
    result.contains(
      "2 10   let builder = StringBuilder::new(size_hint=bytes.length())",
    ),
  )
  assert_false(
    result.contains(
      "+   10 |   let builder = StringBuilder::new(size_hint=bytes.length())",
    ),
  )
}

///|UUID(75a63cec-04c6-4517-b902-6ee11ba6cc17)
test "render keeps UUID-aligned top-level changes on the CST path" {
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
  let result = render("old.mbt", old_source, "new.mbt", new_source)

  assert_true(result.contains("--- old.mbt: line 3"))
  assert_true(result.contains("+++ new.mbt: line 5"))
  assert_true(result.contains("fn inserted() {}"))
  assert_true(result.contains("foo(bar)"))
  assert_true(result.contains("foo(baz(bar))"))
}

///|UUID(827921ba-b988-4e71-a6cb-566e48865be0)
test "render highlights inserted dot access and dot call from the dot" {
  let field_result = render(
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
    options=Options::new(use_color=true),
  )
  assert_true(
    field_result.contains(
      "\u{1b}[90m  obj\u{1b}[39m\u{1b}[32m\u{1b}[1m.field\u{1b}[22m\u{1b}[39m",
    ),
  )

  let call_result = render(
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
    options=Options::new(use_color=true),
  )
  assert_true(
    call_result.contains(
      "\u{1b}[90m  obj\u{1b}[39m\u{1b}[32m\u{1b}[1m.method()\u{1b}[22m\u{1b}[39m",
    ),
  )
}
