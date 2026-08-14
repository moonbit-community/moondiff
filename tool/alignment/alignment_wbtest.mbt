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
test "implementation units cache their source slices" {
  let source =
    #|/// leading a
    #|fn a() {
    #|  first()
    #|}
    #|
    #|/// leading b
    #|fn b() { second() }
  let units = parse_units(source)
  @debug.assert_eq(units.length(), 2)
  @debug.assert_eq(units[0].source, "/// leading a\nfn a() {\n  first()\n}")
  @debug.assert_eq(units[1].source, "/// leading b\nfn b() { second() }")
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
test "unique content hashes align anonymous units but duplicate hashes do not" {
  let old_named = parse_units("fn first() {}\nfn second() {}")
  let new_named = parse_units("fn second() {}\nfn first() {}")
  let old = old_named.map(unit => { ..unit, uuid: None, semantic_key: None })
  let new = new_named.map(unit => { ..unit, uuid: None, semantic_key: None })
  @debug.assert_eq(align_impl_units_by_key(old, new).map(edit_line_summary), [
    "Replace(1->2)", "Replace(2->1)",
  ])

  let duplicate_named = parse_units("fn same() {}\nfn same() {}")
  let duplicate = duplicate_named.map(unit => {
    ..unit,
    uuid: None,
    semantic_key: None,
  })
  let duplicate_edits = align_impl_units_by_key(duplicate, duplicate)
  assert_false(impl_edits_have_replacement(duplicate_edits))
  assert_true(top_level_plan(duplicate, duplicate) is RootList(..))
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
        if find_atom(child, content) is Some(found) {
          return Some(found)
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

///|
fn changed_segment_text(document : @tokdiff.DiffDocument) -> String {
  let buf = StringBuilder::new()
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ContextBlock(_) | IgnoredBlock(_) => ()
        ChangeBlock(rows) =>
          for row in rows {
            match row {
              Paired(old_line, new_line) =>
                for line in [old_line, new_line] {
                  for segment in line.segments {
                    if segment.kind is Changed {
                      buf.write_string(segment.text)
                    }
                  }
                }
              OldOnly(line) | NewOnly(line) =>
                for segment in line.segments {
                  if segment.kind is Changed {
                    buf.write_string(segment.text)
                  }
                }
            }
          }
      }
    }
  }
  buf.to_string()
}

///|
fn ast_segment_summary(
  segments : ArrayView[@tokdiff.DiffSegment],
) -> Array[String] {
  segments.map(segment => {
    let kind = match segment.kind {
      Changed => "changed"
      Unchanged => "unchanged"
      Ignored => "ignored"
    }
    "\{kind}:\{segment.text}"
  })
}

///|
test "AST segments bridge only internal whitespace between changes" {
  @debug.assert_eq(
    ast_segment_summary(
      ast_line_segments("  left \t right  ", Some([(3, 7), (10, 15)])),
    ),
    ["unchanged:  ", "changed:left \t right", "unchanged:  "],
  )

  @debug.assert_eq(
    ast_segment_summary(
      ast_line_segments("left, right", Some([(1, 5), (7, 12)])),
    ),
    ["changed:left", "unchanged:, ", "changed:right"],
  )

  @debug.assert_eq(
    ast_segment_summary(ast_line_segments("  unchanged  ", None)),
    ["unchanged:  unchanged  "],
  )
}

///|
test "top-level plan applies one pairing strategy to reordered declarations" {
  let old_units = parse_units("fn first() {}\nfn second() {}")
  let new_units = parse_units("fn second() {}\nfn first() {}")
  guard top_level_plan(old_units, new_units) is PerUnit(edits) else {
    fail("expected reliable semantic pairs")
  }
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->2)", "Replace(2->1)",
  ])

  let unmatched_old = parse_units("/// trailing old")
  let unmatched_new = parse_units("/// trailing new")
  assert_true(top_level_plan(unmatched_old, unmatched_new) is RootList(..))
}

///|
test "lexical aligned documents preserve original line numbers" {
  let old_source =
    #|fn keep() {}
    #|fn target() {
    #|  old_value()
    #|}
  let new_source =
    #|fn inserted() {}
    #|fn keep() {}
    #|fn target() {
    #|  new_value()
    #|}
  let result = diff_document(old_source, new_source, Lexical, context=0)
  assert_true(result.outcome is Rendered)
  assert_true(result.document.hunks.length() >= 2)
  let changed = result.document.hunks[0]
  @debug.assert_eq((changed.old_start, changed.new_start), (2, 3))
  @debug.assert_eq(changed.header, "@@ -3 +4 @@")

  let ast_result = diff_document(old_source, new_source, Ast, context=0)
  assert_true(ast_result.outcome is Rendered)
  assert_true(ast_result.document.hunks.length() >= 2)
  let ast_changed = ast_result.document.hunks[0]
  @debug.assert_eq((ast_changed.old_start, ast_changed.new_start), (1, 2))
  @debug.assert_eq(ast_changed.header, "@@ -2,3 +3,3 @@")
}

///|
test "lexical pure reorder falls back to a whole-file document" {
  let result = diff_document(
    "fn first() {}\nfn second() {}",
    "fn second() {}\nfn first() {}",
    Lexical,
    context=0,
  )
  guard result.outcome is Fallback(reason) else {
    fail("expected reorder fallback")
  }
  assert_true(reason.contains("reordering"))
  assert_false(result.document.hunks.is_empty())
}

///|
test "AST documents mark only novel source spans as changed" {
  let result = diff_document(
    "fn target() {\n  old_value()\n}",
    "fn target() {\n  new_value()\n}",
    Ast,
    context=0,
  )
  assert_true(result.outcome is Rendered)
  assert_false(result.document.hunks.is_empty())
  let changed = changed_segment_text(result.document)
  assert_true(changed.contains("old_value"), msg=changed)
  assert_true(changed.contains("new_value"), msg=changed)
  assert_false(changed.contains("fn target"), msg=changed)
}

///|
test "AST formatting and top-level reorder are structural empty states" {
  let formatting = diff_document(
    "fn format() { 1 }",
    "fn format() {\n  1\n}",
    Ast,
  )
  assert_true(formatting.outcome is NoStructuralChanges)
  assert_true(formatting.document.hunks.is_empty())

  let reordered = diff_document(
    "fn first() {}\nfn second() {}",
    "fn second() {}\nfn first() {}",
    Ast,
  )
  assert_true(reordered.outcome is NoStructuralChanges)
  assert_true(reordered.document.hunks.is_empty())
}

///|
test "aligned documents distinguish complete and partial lexical fallbacks" {
  let invalid = diff_document("fn broken( {", "fn broken() {}", Ast, context=0)
  guard invalid.outcome is Fallback(parse_reason) else {
    fail("expected parser fallback")
  }
  assert_true(parse_reason.contains("old:"), msg=parse_reason)
  assert_false(invalid.document.hunks.is_empty())

  let limited = diff_document(
    "fn target() { old_value() }",
    "fn target() { new_value() }",
    Ast,
    context=0,
    graph_limit=0,
  )
  guard limited.outcome is PartialFallback([limit_reason]) else {
    fail("expected partial graph fallback")
  }
  assert_true(limit_reason.contains("graph limit exceeded"), msg=limit_reason)
  assert_true(limit_reason.contains("old line 1, new line 1"), msg=limit_reason)
  assert_false(limited.document.hunks.is_empty())

  let root_list_limited = diff_document(
    "/// trailing old",
    "/// trailing new",
    Ast,
    context=0,
    graph_limit=0,
  )
  guard root_list_limited.outcome is Fallback(root_list_reason) else {
    fail("expected whole-document graph fallback")
  }
  assert_true(
    root_list_reason.contains("graph limit exceeded"),
    msg=root_list_reason,
  )
  assert_false(root_list_limited.document.hunks.is_empty())
}

///|
test "aligned documents ignore comments in both modes" {
  let old_source =
    #|/// old docs
    #|fn value() -> Int { 1 // old trailing }
  let new_source =
    #|/// new docs
    #|fn value() -> Int { 1  // new trailing }
  for mode in [Lexical, Ast] {
    let result = diff_document(
      old_source,
      new_source,
      mode,
      ignore_comments=true,
    )
    assert_true(result.outcome is NoNonCommentChanges)
    assert_true(result.document.hunks.is_empty())
  }
  assert_false(
    diff_document(old_source, new_source, Lexical).document.hunks.is_empty(),
  )
}

///|
test "AST comment filtering retains neutral source around code changes" {
  let old_source =
    #|///|UUID(old-id)
    #|fn value() -> Int {
    #|  old_value() // old explanation
    #|}
  let new_source =
    #|///|UUID(new-id)
    #|fn value() -> Int {
    #|  new_value()  // new explanation
    #|}
  let result = diff_document(
    old_source,
    new_source,
    Ast,
    context=1,
    ignore_comments=true,
  )
  let outcome_name = match result.outcome {
    Rendered => "rendered"
    Fallback(_) => "fallback"
    PartialFallback(_) => "partial fallback"
    NoStructuralChanges => "no structural changes"
    NoNonCommentChanges => "no non-comment changes"
  }
  assert_eq(outcome_name, "rendered")
  assert_false(result.document.hunks.is_empty())
  let changed = changed_segment_text(result.document)
  assert_true(changed.contains("old_value"), msg=changed)
  assert_true(changed.contains("new_value"), msg=changed)
  assert_false(changed.contains("explanation"), msg=changed)
  assert_false(changed.contains("old-id"), msg=changed)
  let patch = @tokdiff_text.render_unified_hunks(result.document).join("")
  assert_true(patch.contains("old explanation"), msg=patch)
  assert_true(patch.contains("new explanation"), msg=patch)
}

///|
test "parse failure fallback applies comment filtering" {
  let result = diff_document(
    "fn broken( { old_value // old comment",
    "fn broken( { new_value // new comment",
    Ast,
    context=0,
    ignore_comments=true,
  )
  assert_true(result.outcome is Fallback(_))
  assert_false(result.document.hunks.is_empty())
  let patch = @tokdiff_text.render_unified_hunks(result.document).join("")
  assert_true(patch.contains("old comment"), msg=patch)
  assert_true(patch.contains("new comment"), msg=patch)
  assert_false(changed_segment_text(result.document).contains("comment"))
}
