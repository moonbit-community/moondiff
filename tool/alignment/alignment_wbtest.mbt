///|UUID(4dca0171-1c6a-41f9-b7b6-167bb9c6953d)
fn edit_summary(edit : ImplEdit) -> String {
  match edit {
    Replace(old~, new~) => {
      let old_uuid = old.uuid.unwrap_or("none")
      let new_uuid = new.uuid.unwrap_or("none")
      "Replace(\{old_uuid}->\{new_uuid})"
    }
    Delete(old) => {
      let old_uuid = old.uuid.unwrap_or("none")
      "Delete(\{old_uuid})"
    }
    Insert(new) => {
      let new_uuid = new.uuid.unwrap_or("none")
      "Insert(\{new_uuid})"
    }
  }
}

///|UUID(42a6fa59-8e84-4dad-aee4-0435e8c07d32)
fn edit_line_summary(edit : ImplEdit) -> String {
  match edit {
    Replace(old~, new~) => "Replace(\{old.start_line}->\{new.start_line})"
    Delete(old) => "Delete(\{old.start_line})"
    Insert(new) => "Insert(\{new.start_line})"
  }
}

///|UUID(1bfc1fdd-7d6e-45d9-9a3d-12672bcd26bd)
fn parse_units(source : String) -> Array[ImplUnit] {
  let result = @cst.parse_structure(source)
  if !result.diagnostics_view().is_empty() {
    panic()
  }
  collect_impl_units(source, result.root())
}

///|
test "UUID extraction accepts only exact own-line markers" {
  let standard_uuid = "8bf07bdd-6cbd-4d64-8b82-a40f69970b25"
  let cases : Array[(String, String?)] = [
    ("///|UUID(0)", Some("0")),
    ("///|UUID(\{standard_uuid})", Some(standard_uuid)),
    ("// UUID(ordinary)", None),
    ("/// Documentation mentions UUID(narrative).", None),
    ("///UUID(no-pipe)", None),
    ("///|UUID()", None),
    ("///|UUID(has space)", None),
    ("///| UUID(spaced-prefix)", None),
    ("  ///|UUID(indented)", None),
    ("///|UUID(trailing-space) ", None),
    ("///|UUID(trailing-text) extra", None),
    ("///|UUID(under_score)", None),
  ]
  for entry in cases {
    let (comment, expected) = entry
    let units = parse_units("\{comment}\nfn tagged() {}")
    @debug.assert_eq(units.length(), 1)
    @debug.assert_eq(units[0].uuid, expected)
  }
}

///|
test "UUID markers must be declaration-leading own-line trivia" {
  let inline_units = parse_units(
    "fn before() {} ///|UUID(inline)\nfn after() {}",
  )
  @debug.assert_eq(inline_units.length(), 2)
  @debug.assert_eq(inline_units[0].uuid, None)
  @debug.assert_eq(inline_units[1].uuid, None)

  let orphan_units = parse_units("fn tagged() {}\n///|UUID(orphan)")
  @debug.assert_eq(orphan_units.length(), 2)
  @debug.assert_eq(orphan_units[0].uuid, None)
  @debug.assert_eq(orphan_units[1].uuid, None)
}

///|
test "invalid UUID-like comments do not override semantic reordering" {
  let cases : Array[(String, String)] = [
    ("// UUID(first)", "// UUID(second)"),
    (
      "/// Documentation mentions UUID(first).", "/// Documentation mentions UUID(second).",
    ),
    ("///UUID(first)", "///UUID(second)"),
    ("///| UUID(first)", "///| UUID(second)"),
    ("  ///|UUID(first)", "  ///|UUID(second)"),
    ("///|UUID(first) trailing", "///|UUID(second) trailing"),
  ]
  for entry in cases {
    let (first_comment, second_comment) = entry
    let old_source = "\{first_comment}\nfn a() {}\n\{second_comment}\nfn b() {}"
    let new_source = "\{first_comment}\nfn b() {}\n\{second_comment}\nfn a() {}"
    let edits = align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
    )
    @debug.assert_eq(edits.map(edit_line_summary), [
      "Replace(1->3)", "Replace(3->1)",
    ])
  }
}

///|
test "new CST implementation kinds retain semantic alignment keys" {
  let cases = [
    ("import { \"pkg/core\" }", "import:"),
    ("import { \"pkg/test\" } for \"test\"", "import:\"test\""),
    (
      "extend @pkg.Type with @pkg.Trait::{method}", "extend:@pkg.Type:@pkg.Trait",
    ),
    ("fn f() {}", "fn:::f"),
    ("fn Widget::method() {}", "fn:Widget::method"),
    ("fn &Widget::method() {}", "fn:&Widget::method"),
    ("let value = 1", "let:value"),
    ("const VALUE = 1", "const:VALUE"),
    ("type Alias = Int", "type:Alias"),
    ("struct Record {}", "type:Record"),
    ("enum Variant { A }", "type:Variant"),
    ("trait Show {}", "trait:Show"),
    ("test \"named\" {}", "test:\"named\""),
    ("impl Eq for Int", "impl:Int:Eq"),
    ("impl @debug.Debug for T", "impl:T:@debug.Debug"),
    (
      "impl Eq for Int with equal(self, other) { true }", "impl-fn:Int:Eq::equal",
    ),
    ("enumview V { C } for T with view(x) { x }", "view:V:view"),
    ("using @pkg {func as func2}", "using:@pkg:{func as func2}"),
  ]
  for entry in cases {
    let (source, expected) = entry
    let units = parse_units(source)
    @debug.assert_eq(units.length(), 1)
    @debug.assert_eq(units[0].semantic_key, Some(expected))
  }
}

///|UUID(0c6b3f16-db94-47b3-a98d-6703cfaa9863)
test "align_impl_units_by_uuid aligns UUID blocks before inner structural diff" {
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

  let edits = align_impl_units_by_uuid(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_summary), [
    "Replace(11111111-1111-1111-1111-111111111111->11111111-1111-1111-1111-111111111111)",
    "Replace(22222222-2222-2222-2222-222222222222->22222222-2222-2222-2222-222222222222)",
    "Insert(99999999-9999-9999-9999-999999999999)",
  ])
}

///|UUID(17292d71-1f7b-4cc1-bbcd-dd2bc7cb2d3f)
test "align_impl_units_by_key matches no-UUID functions after insertion" {
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

  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->2)", "Replace(2->3)", "Insert(1)",
  ])
}

///|UUID(51f6f23d-97bc-4936-ae62-a0c7f5f76c6e)
test "align_impl_units_by_key matches no-UUID functions after reordering" {
  let old_source =
    #|fn a() {}
    #|fn b() {}
  let new_source =
    #|fn b() {}
    #|fn a() {}

  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->2)", "Replace(2->1)",
  ])
}

///|UUID(0982674c-8c35-465a-93af-e316ca662015)
test "align_impl_units_by_key uses semantic key when UUID is missing on one side" {
  let old_source =
    #|///|UUID(22222222-2222-2222-2222-222222222222)
    #|fn target() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn target() {
    #|  foo(baz(bar))
    #|}

  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), ["Replace(1->1)"])
}

///|UUID(4fbb6c68-67c1-4ab6-b063-a7e463b207ca)
test "align_impl_units_by_key pairs duplicate semantic keys by occurrence order" {
  let old_source =
    #|fn dup() {
    #|  first()
    #|}
    #|fn dup() {
    #|  second()
    #|}
  let new_source =
    #|fn dup() {
    #|  first_changed()
    #|}
    #|fn dup() {
    #|  second_changed()
    #|}

  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Replace(4->4)",
  ])
}

///|
test "align_impl_units_by_key distinguishes methods on the same type" {
  let old_source =
    #|fn Widget::first() {
    #|  old_first()
    #|}
    #|fn Widget::second() {
    #|  old_second()
    #|}
  let new_source =
    #|fn Widget::second() {
    #|  new_second()
    #|}
    #|fn Widget::first() {
    #|  new_first()
    #|}

  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->4)", "Replace(4->1)",
  ])
}

///|
fn find_atom(node : @syntax.Syntax, content : String) -> @syntax.Syntax? {
  match node {
    @syntax.Syntax::Atom(content=actual, ..) =>
      if actual == content {
        Some(node)
      } else {
        None
      }
    @syntax.Syntax::List(children~, ..) => {
      for child in children {
        match find_atom(child, content) {
          Some(found) => return Some(found)
          None => ()
        }
      }
      None
    }
  }
}

///|UUID(5899396d-f317-4aa3-bdae-68ae6ff257e5)
test "CST wrappers do not hide inserted sibling statements" {
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
  let old_units = parse_units(old_source)
  let new_units = parse_units(new_source)
  if old_units.length() != 1 || new_units.length() != 1 {
    panic()
  }

  let lhs_roots = [old_units[0].root]
  let rhs_roots = [new_units[0].root]
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, 3_000_000) catch {
    _ => panic()
  }

  let rhs_inserted_atom = find_atom(rhs_roots[0], "5").unwrap()
  assert_true(
    change_map.get(rhs_inserted_atom) is Some(@syntax.ChangeKind::Novel),
  )
  let lhs_string = find_atom(lhs_roots[0], "\"Hello, world!\"").unwrap()
  match change_map.get(lhs_string) {
    Some(@syntax.ChangeKind::Unchanged(opposite)) =>
      @debug.assert_eq(opposite.content_id(), lhs_string.content_id())
    _ => panic()
  }
}
