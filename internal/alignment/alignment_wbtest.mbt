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
    Replace(old~, new~) =>
      "Replace(\{old.range.start + 1}->\{new.range.start + 1})"
    Delete(old) => "Delete(\{old.range.start + 1})"
    Insert(new) => "Insert(\{new.range.start + 1})"
  }
}

///|
fn edit_declaration_summary(edit : ImplEdit) -> String {
  fn name(unit : ImplUnit) -> String {
    unit.fuzzy.map(info => info.name).unwrap_or("none")
  }

  match edit {
    Replace(old~, new~) => "Replace(\{name(old)}->\{name(new)})"
    Delete(old) => "Delete(\{name(old)})"
    Insert(new) => "Insert(\{name(new)})"
  }
}

///|UUID(1bfc1fdd-7d6e-45d9-9a3d-12672bcd26bd)
fn parse_units(source : String) -> Array[ImplUnit] {
  let result = @cst.parse_structure(source)
  if !result.diagnostics_view().is_empty() {
    panic()
  }
  collect_impl_units_detailed(source, result.root(), false).units
}

///|
test "implementation units keep only their declaration keyword source line" {
  let source =
    #|/// Leading documentation.
    #|///|UUID(context-id)
    #|#deprecated
    #|pub fn CloserIndex::add(
    #|  self : CloserIndex,
    #|  key : Closer,
    #|) -> Unit {
    #|  ignore(key)
    #|}
    #|let singleton = 1
    #|/// trailing trivia without a declaration
  let units = parse_units(source)
  assert_eq(units.length(), 3)
  assert_true(units[0].context == Some("pub fn CloserIndex::add("))
  assert_true(units[1].context == Some("let singleton = 1"))
  assert_true(units[2].context is None)
}

///|
fn unit_source_for_test(source : String, unit : ImplUnit) -> String {
  let lines = @source_text.split_lines(source)
  lines[unit.range.start:unit.range.start + unit.range.len].join("\n")
}

///|
fn alignment_test_budget() -> @computation.Budget {
  @computation.Budget::new(@computation.default_limit())
}

///|
fn align_impl_units_by_key(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  use_uuid? : Bool = true,
) -> Array[ImplEdit] {
  align_impl_units_by_key_impl(
    old_units,
    new_units,
    alignment_test_budget(),
    use_uuid~,
  ) catch {
    @computation.LimitExceeded(..) => panic()
  }
}

///|
fn long_free_declaration(name : String, finish? : String = "finish") -> String {
  let source =
    $|fn \{name}(input : Input) -> Output {
    $|  let first = step_one(input)
    $|  let second = step_two(first)
    $|  let third = step_three(second)
    $|  let fourth = step_four(third)
    $|  let fifth = step_five(fourth)
    $|  \{finish}(first, second, third, fourth, fifth)
    $|}
  source
}

///|
fn long_method_declaration(receiver : String, name : String) -> String {
  let source =
    $|fn \{receiver}::\{name}(self : Worker, input : Input) -> Output {
    $|  let first = step_one(input)
    $|  let second = step_two(first)
    $|  let third = step_three(second)
    $|  let fourth = step_four(third)
    $|  let fifth = step_five(fourth)
    $|  finish(first, second, third, fourth, fifth)
    $|}
  source
}

///|
fn distinct_long_free_declaration(name : String, marker : String) -> String {
  let source =
    $|fn \{name}(input : Input) -> Output {
    $|  let \{marker}_first = \{marker}_step_one(input)
    $|  let \{marker}_second = \{marker}_step_two(\{marker}_first)
    $|  let \{marker}_third = \{marker}_step_three(\{marker}_second)
    $|  let \{marker}_fourth = \{marker}_step_four(\{marker}_third)
    $|  let \{marker}_fifth = \{marker}_step_five(\{marker}_fourth)
    $|  \{marker}_finish(
    $|    \{marker}_first,
    $|    \{marker}_second,
    $|    \{marker}_third,
    $|    \{marker}_fourth,
    $|    \{marker}_fifth,
    $|  )
    $|}
  source
}

///|
fn many_independent_extraction_sources(count : Int) -> (String, String) {
  let old_declarations : Array[String] = []
  let new_declarations : Array[String] = []
  for i in 0..<count {
    let name = "target_\{i}"
    let helper = "\{name}_helper"
    let marker = "body_\{i}"
    old_declarations.push(distinct_long_free_declaration(name, marker))
    let wrapper =
      $|fn \{name}(input : Input) -> Output {
      $|  \{helper}(input)
      $|}
    new_declarations.push(wrapper)
    new_declarations.push(distinct_long_free_declaration(helper, marker))
  }
  (old_declarations.join("\n"), new_declarations.join("\n"))
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
  @debug.assert_eq(
    unit_source_for_test(source, units[0]),
    "/// leading a\nfn a() {\n  first()\n}",
  )
  @debug.assert_eq(
    unit_source_for_test(source, units[1]),
    "/// leading b\nfn b() { second() }",
  )
}

///|
test "ignored test collection excludes roots and records leading trivia" {
  let source =
    #|fn production() {}
    #|
    #|/// test docs
    #|///|UUID(test-id)
    #|async test "sample" {
    #|  inspect(1)
    #|}
  let parsed = @cst.parse_structure(source)
  assert_true(parsed.diagnostics_view().is_empty())
  let collection = collect_impl_units_detailed(source, parsed.root(), true)
  @debug.assert_eq(collection.units.length(), 1)
  @debug.assert_eq(collection.units[0].semantic_key, Some("fn:::production"))
  @debug.assert_eq(collection.ignored_tests.length(), 1)
  let ignored = collection.ignored_tests[0]
  @debug.assert_eq((ignored.start.lnum, ignored.start.column()), (3, 1))
  @debug.assert_eq((ignored.end.lnum, ignored.end.column()), (7, 2))
}

///|
test "ignored test collection preserves ordinary leading comments" {
  let source =
    #|fn production() {}
    #|// retained line comment
    #|// retained second comment
    #|/// test docs
    #|///|UUID(test-id)
    #|test "sample" { inspect(1) }
  let parsed = @cst.parse_structure(source)
  assert_true(parsed.diagnostics_view().is_empty())
  let collection = collect_impl_units_detailed(source, parsed.root(), true)
  @debug.assert_eq(collection.units.length(), 2)
  @debug.assert_eq(collection.units[1].semantic_key, None)
  @debug.assert_eq(
    unit_source_for_test(source, collection.units[1]),
    "// retained line comment\n// retained second comment",
  )
  @debug.assert_eq(collection.ignored_tests.length(), 1)
  let ignored = collection.ignored_tests[0]
  @debug.assert_eq((ignored.start.lnum, ignored.start.column()), (4, 1))
  @debug.assert_eq((ignored.end.lnum, ignored.end.column()), (6, 29))
}

///|
test "ignored test docs stop at a blank line" {
  let source =
    #|/// retained production docs
    #|
    #|/// owned test docs
    #|test "sample" { inspect(1) }
  let parsed = @cst.parse_structure(source)
  assert_true(parsed.diagnostics_view().is_empty())
  let collection = collect_impl_units_detailed(source, parsed.root(), true)
  @debug.assert_eq(collection.units.length(), 1)
  @debug.assert_eq(
    unit_source_for_test(source, collection.units[0]),
    "/// retained production docs",
  )
  @debug.assert_eq(collection.ignored_tests.length(), 1)
  @debug.assert_eq(collection.ignored_tests[0].start.lnum, 3)
}

///|
test "ordinary comments interrupt ignored test doc ownership" {
  let source =
    #|/// retained earlier docs
    #|// ordinary ownership boundary
    #|/// owned test docs
    #|///|UUID(test-id)
    #|test "sample" { inspect(1) }
  let parsed = @cst.parse_structure(source)
  assert_true(parsed.diagnostics_view().is_empty())
  let collection = collect_impl_units_detailed(source, parsed.root(), true)
  @debug.assert_eq(collection.units.length(), 1)
  @debug.assert_eq(
    unit_source_for_test(source, collection.units[0]),
    "/// retained earlier docs\n// ordinary ownership boundary",
  )
  @debug.assert_eq(collection.ignored_tests.length(), 1)
  @debug.assert_eq(collection.ignored_tests[0].start.lnum, 3)
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
  let old = old_named.map(unit => { ..unit, uuid: None, semantic_key: None, })
  let new = new_named.map(unit => { ..unit, uuid: None, semantic_key: None, })
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
  assert_true(
    top_level_plan_impl(duplicate, duplicate, alignment_test_budget())
    is RootList(..),
  )
}

///|
test "fuzzy metadata replaces only the declaration name" {
  let units = parse_units(
    "fn &JobHandle::spawn_unix(path : String) { launch(path) }",
  )
  guard units is [{ fuzzy: Some(info), .. }] else {
    fail("expected fuzzy declaration metadata")
  }
  assert_eq(info.name, "spawn_unix")
  assert_eq(info.owner, "method:&JobHandle")
  assert_true(find_atom(info.root, impl_fuzzy_name_marker) is Some(_))
  assert_true(find_atom(info.root, "JobHandle") is Some(_))
  assert_true(find_atom(info.root, "path") is Some(_))

  let excluded = [
    "import { \"pkg/core\" }", "extend @pkg.Type with @pkg.Trait::{method}", "using @pkg { method }",
    "/// trailing comment",
  ]
  for source in excluded {
    let units = parse_units(source)
    assert_true(units.length() == 1)
    assert_true(units[0].fuzzy is None)
  }
}

///|
test "body trigrams ignore comments and normalize recursive call names" {
  let old_source =
    #|fn walk(input : Input) -> Output {
    #|  let first = step_one(input)
    #|  let second = step_two(first)
    #|  // old explanation
    #|  let third = step_three(second)
    #|  walk(third)
    #|}
  let new_source =
    #|fn walk_with_state(input : Input, state : State) -> Output {
    #|  let first = step_one(input)
    #|  // new explanation
    #|  let second = step_two(first)
    #|  let third = step_three(second)
    #|  walk_with_state(third)
    #|}
  guard parse_units(old_source)[0].fuzzy is Some(old_info) &&
    old_info.body_input is Some(old_input) &&
    parse_units(new_source)[0].fuzzy is Some(new_info) &&
    new_info.body_input is Some(new_input) else {
    fail("expected function body metadata")
  }
  let old_body = make_impl_fuzzy_body(old_input)
  let new_body = make_impl_fuzzy_body(new_input)
  assert_true(old_body.mass >= impl_extraction_min_body_mass)
  assert_eq(old_body.mass, new_body.mass)
  assert_eq(impl_body_continuity(old_body, new_body), 1000)
}

///|
test "body fingerprints are charged and cached once per alignment" {
  let units = parse_units(long_free_declaration("target"))
  guard units[0].fuzzy is Some(info) && info.body_input is Some(input) else {
    fail("expected function body input")
  }
  let work = @cmp.maximum(
    input.node.source_span.1 - input.node.source_span.0,
    0,
  ).reinterpret_as_uint()
  assert_true(work > 0)
  let rejected_cache : Array[ImplFuzzyBody?] = Array::make(units.length(), None)
  let insufficient = @computation.Budget::new(work - 1)
  try impl_fuzzy_body_at(units, 0, rejected_cache, insufficient) catch {
    @computation.LimitExceeded(stage~, limit~) => {
      assert_true(stage is TopLevelAlignment)
      assert_eq(limit, work - 1)
      assert_true(rejected_cache[0] is None)
    }
  } noraise {
    _ => fail("expected construction to be rejected before caching")
  }
  let cache : Array[ImplFuzzyBody?] = Array::make(units.length(), None)
  let budget = @computation.Budget::new(work)
  guard impl_fuzzy_body_at(units, 0, cache, budget) is Some(first) &&
    impl_fuzzy_body_at(units, 0, cache, budget) is Some(second) else {
    fail("expected cached body fingerprints")
  }
  assert_eq(first.mass, second.mass)
  try budget.charge(1U, TopLevelAlignment) catch {
    @computation.LimitExceeded(stage~, limit~) => {
      assert_true(stage is TopLevelAlignment)
      assert_eq(limit, work)
    }
  } noraise {
    _ => fail("expected the body fingerprint charge to exhaust the budget")
  }
}

///|
test "semantic extraction filters missing helpers before body fingerprint work" {
  let old_source = long_free_declaration("target")
  let new_source = long_free_declaration("target", finish="finish_changed")
  let budget = @computation.Budget::new(0)
  let edits = align_impl_units_by_key_impl(
    parse_units(old_source),
    parse_units(new_source),
    budget,
  )
  @debug.assert_eq(edits.map(edit_declaration_summary), [
    "Replace(target->target)",
  ])
}

///|
test "direct self delegates include return-self cascade calls" {
  fn inspect_delegate(source : String) -> (String?, String?) raise {
    let parsed = @cst.parse_structure(source)
    guard parsed.diagnostics_view().is_empty() &&
      first_child_node(parsed.root(), "item") is Some(wrapper_node) &&
      impl_function_body(wrapper_node) is Some(wrapper_body) &&
      final_impl_body_expression(wrapper_body) is Some(wrapper_tail) else {
      fail("expected a valid wrapper tail expression")
    }
    (
      first_child_text(source, wrapper_tail, "op"),
      direct_self_delegate(source, wrapper_tail),
    )
  }

  let dot_source = "fn Worker::wrapper(self : Worker) { self.helper() }"
  let cascade_source = "fn Worker::wrapper(self : Worker) { self..helper() }"
  @debug.assert_eq(inspect_delegate(dot_source), (None, Some("helper")))
  @debug.assert_eq(
    inspect_delegate(cascade_source),
    (Some(".."), Some("helper")),
  )
}

///|
test "semantic extraction pairs an old method with an adjacent helper" {
  let old_source =
    #|fn ThreadSet::remove_duplicates(self : ThreadSet, next : Expr) -> ThreadSet {
    #|  let seen = @hashset.HashSet([])
    #|  for thread in self; result = ts_empty {
    #|    match thread {
    #|      End(_) => break result + ts_one(thread)
    #|      Exp(_, { def: Eps, .. }) =>
    #|        if !seen.contains(next.id) {
    #|          seen.add(next.id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Exp(_, { id, .. }) =>
    #|        if !seen.contains(id) {
    #|          seen.add(id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Seq(pref, first, next) => {
    #|        let first_dedup = first.remove_duplicates(next)
    #|        continue result + ts_seq(pref, first_dedup, next)
    #|      }
    #|    }
    #|  } nobreak {
    #|    result
    #|  }
    #|}
  let new_source =
    #|fn ThreadSet::remove_duplicates(self : ThreadSet, next : Expr) -> ThreadSet {
    #|  let seen = @hashset.HashSet([])
    #|  self.remove_duplicates_with_seen(next, seen)
    #|}
    #|fn ThreadSet::remove_duplicates_with_seen(
    #|  self : ThreadSet,
    #|  next : Expr,
    #|  seen : @hashset.HashSet[ExprId],
    #|) -> ThreadSet {
    #|  for thread in self; result = ts_empty {
    #|    match thread {
    #|      End(_) => break result + ts_one(thread)
    #|      Exp(_, { def: Eps, .. }) =>
    #|        if !seen.contains(next.id) {
    #|          seen.add(next.id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Exp(_, { id, .. }) =>
    #|        if !seen.contains(id) {
    #|          seen.add(id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Seq(pref, first, next) => {
    #|        let first_dedup = first.remove_duplicates_with_seen(next, seen)
    #|        continue result + ts_seq(pref, first_dedup, next)
    #|      }
    #|    }
    #|  } nobreak {
    #|    result
    #|  }
    #|}
  let old = parse_units(old_source)
  let new = parse_units(new_source)
  let parsed_new = @cst.parse_structure(new_source)
  guard first_child_node(parsed_new.root(), "item") is Some(wrapper_node) &&
    impl_function_body(wrapper_node) is Some(wrapper_body_node) &&
    final_impl_body_expression(wrapper_body_node) is Some(wrapper_tail) else {
    fail("expected wrapper tail expression")
  }
  assert_eq(
    direct_self_delegate(new_source, wrapper_tail),
    Some("remove_duplicates_with_seen"),
    msg="tail kind=\{Repr(wrapper_tail.kind)}, text=\{cst_node_text(new_source, wrapper_tail)}, " +
      "receiver=\{first_child_node(wrapper_tail, "self").map(node => cst_node_text(new_source, node)).unwrap_or("missing")}, " +
      "token=\{Repr(first_child_text(new_source, wrapper_tail, "token"))}, " +
      "delegate=\{Repr(direct_self_delegate(new_source, wrapper_tail))}",
  )
  guard old[0].fuzzy is Some(old_info) &&
    old_info.body_input is Some(old_input) &&
    new[0].fuzzy is Some(wrapper_info) &&
    wrapper_info.body_input is Some(wrapper_input) &&
    new[1].fuzzy is Some(helper_info) &&
    helper_info.body_input is Some(helper_input) else {
    fail("expected method body metadata")
  }
  let old_body = make_impl_fuzzy_body(old_input)
  let wrapper_body = make_impl_fuzzy_body(wrapper_input)
  let helper_body = make_impl_fuzzy_body(helper_input)
  let edits = align_impl_units_by_key(old, new)
  assert_true(
    edits.map(edit_declaration_summary) ==
    [
      "Replace(remove_duplicates->remove_duplicates_with_seen)", "Insert(remove_duplicates)",
    ],
    msg="old=\{old_body.mass}, wrapper=\{wrapper_body.mass}, helper=\{helper_body.mass}, " +
      "tail=\{wrapper_info.tail_delegate.map(delegate => delegate.target).unwrap_or("none")}, helper_score=\{impl_body_continuity(old_body, helper_body)}, " +
      "wrapper_score=\{impl_body_continuity(old_body, wrapper_body)}, edits=\{edits.map(edit_declaration_summary).join(", ")}",
  )
}

///|
test "semantic extraction accepts a return-self cascade wrapper" {
  let old_source =
    #|fn Worker::target(self : Worker, input : Input) -> Worker {
    #|  let first = step_one(input)
    #|  let second = step_two(first)
    #|  let third = step_three(second)
    #|  let fourth = step_four(third)
    #|  let fifth = step_five(fourth)
    #|  finish(first, second, third, fourth, fifth)
    #|  self
    #|}
  let wrapper =
    #|fn Worker::target(self : Worker, input : Input) -> Worker {
    #|  self..target_helper(input)
    #|}
  let helper =
    #|fn Worker::target_helper(self : Worker, input : Input) -> Unit {
    #|  let first = step_one(input)
    #|  let second = step_two(first)
    #|  let third = step_three(second)
    #|  let fourth = step_four(third)
    #|  let fifth = step_five(fourth)
    #|  finish(first, second, third, fourth, fifth)
    #|}
  let new_source = wrapper + "\n" + helper
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_declaration_summary), [
    "Replace(target->target_helper)", "Insert(target)",
  ])
}

///|
test "semantic extraction supports a preceding free helper and explicit return" {
  let old_source =
    #|fn remove_duplicates(threads : ThreadSet, next : Expr) -> ThreadSet {
    #|  let seen = @hashset.HashSet([])
    #|  for thread in threads; result = ts_empty {
    #|    match thread {
    #|      End(_) => break result + ts_one(thread)
    #|      Exp(_, { def: Eps, .. }) =>
    #|        if !seen.contains(next.id) {
    #|          seen.add(next.id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Exp(_, { id, .. }) =>
    #|        if !seen.contains(id) {
    #|          seen.add(id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Seq(pref, first, next) => {
    #|        let first_dedup = remove_duplicates(first, next)
    #|        continue result + ts_seq(pref, first_dedup, next)
    #|      }
    #|    }
    #|  } nobreak {
    #|    result
    #|  }
    #|}
  let new_source =
    #|fn remove_duplicates_with_seen(
    #|  threads : ThreadSet,
    #|  next : Expr,
    #|  seen : @hashset.HashSet[ExprId],
    #|) -> ThreadSet {
    #|  for thread in threads; result = ts_empty {
    #|    match thread {
    #|      End(_) => break result + ts_one(thread)
    #|      Exp(_, { def: Eps, .. }) =>
    #|        if !seen.contains(next.id) {
    #|          seen.add(next.id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Exp(_, { id, .. }) =>
    #|        if !seen.contains(id) {
    #|          seen.add(id)
    #|          continue result + ts_one(thread)
    #|        } else {
    #|          continue result
    #|        }
    #|      Seq(pref, first, next) => {
    #|        let first_dedup = remove_duplicates_with_seen(first, next, seen)
    #|        continue result + ts_seq(pref, first_dedup, next)
    #|      }
    #|    }
    #|  } nobreak {
    #|    result
    #|  }
    #|}
    #|fn remove_duplicates(threads : ThreadSet, next : Expr) -> ThreadSet {
    #|  let seen = @hashset.HashSet([])
    #|  return remove_duplicates_with_seen(threads, next, seen)
    #|}
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_declaration_summary), [
    "Replace(remove_duplicates->remove_duplicates_with_seen)", "Insert(remove_duplicates)",
  ])
}

///|
test "semantic extraction rejects weak or partial split evidence" {
  let old_long = long_free_declaration("target")
  let helper_long = long_free_declaration("target_helper")
  let unrelated_wrapper =
    #|fn target(input : Input) -> Output {
    #|  unrelated(input)
    #|}
  let delegating_wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let retained_wrapper =
    #|fn target(input : Input) -> Output {
    #|  let first = step_one(input)
    #|  let second = step_two(first)
    #|  let third = step_three(second)
    #|  target_helper(third)
    #|}
  let conditional_wrapper =
    #|fn target(input : Input) -> Output {
    #|  if enabled() { target_helper(input) } else { fallback(input) }
    #|}
  let tiny_split =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
    #|fn target_helper(input : Input) -> Output { step_one(input) }
  let cases : Array[(String, String, String)] = [
    (
      "ordinary same-name edit",
      old_long,
      long_free_declaration("target", finish="finish_changed"),
    ),
    (
      "wrapper calls an unrelated helper",
      old_long,
      unrelated_wrapper + "\n" + helper_long,
    ),
    (
      "helper is not adjacent",
      old_long,
      delegating_wrapper + "\nfn stable() {}\n" + helper_long,
    ),
    (
      "wrapper retains too much old body",
      old_long,
      retained_wrapper + "\n" + helper_long,
    ),
    (
      "wrapper delegates conditionally",
      old_long,
      conditional_wrapper + "\n" + helper_long,
    ),
    (
      "old body is too small", "fn target(input : Input) -> Output { step_one(input) }",
      tiny_split,
    ),
  ]
  for entry in cases {
    let (label, old_source, new_source) = entry
    let edits = align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
    )
    let summaries = edits.map(edit_declaration_summary)
    assert_true(
      !summaries.is_empty() && summaries[0] == "Replace(target->target)",
      msg="\{label}: \{summaries.join(", ")}",
    )
    assert_false(
      summaries.contains("Replace(target->target_helper)"),
      msg="\{label}: \{summaries.join(", ")}",
    )
  }
}

///|
test "semantic extraction requires compatible ownership and a unique self delegate" {
  let ref_old = long_method_declaration("&Worker", "target")
  let ref_wrapper =
    #|fn &Worker::target(self : Worker, input : Input) -> Output {
    #|  self.target_helper(input)
    #|}
  let value_helper = long_method_declaration("Worker", "target_helper")
  let value_old = long_method_declaration("Worker", "target")
  let other_wrapper =
    #|fn Worker::target(self : Worker, input : Input) -> Output {
    #|  other.target_helper(input)
    #|}
  let bare_method_wrapper =
    #|fn Worker::target(self : Worker, input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let value_helper_same_owner = long_method_declaration(
    "Worker", "target_helper",
  )
  let ambiguous_helper = long_free_declaration("target_helper")
  let ambiguous_wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let cases : Array[(String, String, String)] = [
    ("reference owner differs", ref_old, ref_wrapper + "\n" + value_helper),
    (
      "method receiver is not self",
      value_old,
      other_wrapper + "\n" + value_helper_same_owner,
    ),
    (
      "method helper is called without self",
      value_old,
      bare_method_wrapper + "\n" + value_helper_same_owner,
    ),
    (
      "two adjacent helpers satisfy the delegate name",
      long_free_declaration("target"),
      ambiguous_helper + "\n" + ambiguous_wrapper + "\n" + ambiguous_helper,
    ),
  ]
  for entry in cases {
    let (label, old_source, new_source) = entry
    let summaries = align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
    ).map(edit_declaration_summary)
    assert_true(
      !summaries.is_empty() && summaries[0] == "Replace(target->target)",
      msg="\{label}: \{summaries.join(", ")}",
    )
  }
}

///|
test "semantic extraction requires an unoccupied helper with one clear old owner" {
  let wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let tied_old = long_free_declaration("target") +
    "\n" +
    long_free_declaration("competitor")
  let tied_new = wrapper +
    "\n" +
    long_free_declaration("target_helper") +
    "\n" +
    long_free_declaration("competitor")
  @debug.assert_eq(
    align_impl_units_by_key(parse_units(tied_old), parse_units(tied_new)).map(
      edit_declaration_summary,
    ),
    [
      "Replace(target->target)", "Replace(competitor->competitor)", "Insert(target_helper)",
    ],
  )

  let occupied_old = long_free_declaration("target") +
    "\n" +
    long_free_declaration("target_helper")
  let occupied_new = wrapper +
    "\n" +
    long_free_declaration("target_helper", finish="finish_changed")
  @debug.assert_eq(
    align_impl_units_by_key(
      parse_units(occupied_old),
      parse_units(occupied_new),
    ).map(edit_declaration_summary),
    ["Replace(target->target)", "Replace(target_helper->target_helper)"],
  )
}

///|
test "semantic extraction ambiguity work uses the file budget" {
  let extraction_count = 24
  let (old_source, new_source) = many_independent_extraction_sources(
    extraction_count,
  )
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  let mut replacements = 0
  let mut insertions = 0
  for edit in edits {
    match edit {
      Replace(old~, new~) => {
        guard old.fuzzy is Some(old_info) && new.fuzzy is Some(new_info) else {
          fail("expected fuzzy declaration metadata")
        }
        assert_eq(new_info.name, "\{old_info.name}_helper")
        replacements += 1
      }
      Insert(_) => insertions += 1
      Delete(_) =>
        fail("independent extractions must retain every old declaration")
    }
  }
  assert_eq(replacements, extraction_count)
  assert_eq(insertions, extraction_count)

  let calculation = calculate_diff_document_with_limit(
    old_source, new_source, "old", "new", 0, 3_000_000, false, 1,
  )
  guard calculation.document is Whole(fragment) else {
    fail("expected top-level budget exhaustion to produce Whole")
  }
  guard fragment.fallbacks
    is [ComputationLimitExceeded(stage=TopLevelAlignment, limit=1)] else {
    fail("expected extraction ambiguity work to use the top-level budget")
  }
  assert_false(fragment.document.hunks.is_empty())
}

///|
test "duplicate semantic keys and UUID anchors cannot be challenged" {
  let duplicate_old = long_free_declaration("dup") +
    "\n" +
    long_free_declaration("dup")
  let duplicate_wrapper =
    #|fn dup(input : Input) -> Output {
    #|  dup_helper(input)
    #|}
  let duplicate_new = duplicate_wrapper +
    "\n" +
    long_free_declaration("dup_helper") +
    "\n" +
    long_free_declaration("dup", finish="finish_changed")
  @debug.assert_eq(
    align_impl_units_by_key(
      parse_units(duplicate_old),
      parse_units(duplicate_new),
    ).map(edit_declaration_summary),
    ["Replace(dup->dup)", "Replace(dup->dup)", "Insert(dup_helper)"],
  )

  let uuid_old = "///|UUID(extraction-target)\n" +
    long_free_declaration("target")
  let uuid_wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let uuid_new = "///|UUID(extraction-target)\n" +
    uuid_wrapper +
    "\n" +
    long_free_declaration("target_helper")
  @debug.assert_eq(
    align_impl_units_by_key(parse_units(uuid_old), parse_units(uuid_new)).map(
      edit_declaration_summary,
    ),
    ["Replace(target->target)", "Insert(target_helper)"],
  )
}

///|
test "semantic extraction respects conflicting helper UUIDs" {
  let old_source = "///|UUID(old-target)\n" + long_free_declaration("target")
  let wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let new_source = wrapper +
    "\n///|UUID(new-helper)\n" +
    long_free_declaration("target_helper")
  @debug.assert_eq(
    align_impl_units_by_key(parse_units(old_source), parse_units(new_source)).map(
      edit_summary,
    ),
    ["Replace(old-target->none)", "Insert(new-helper)"],
  )
  @debug.assert_eq(
    align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
      use_uuid=false,
    ).map(edit_summary),
    ["Replace(old-target->new-helper)", "Insert(none)"],
  )
}

///|
test "a displaced wrapper cannot reenter exact or fuzzy matching" {
  let other =
    #|fn other(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let old_source = other + "\n" + long_free_declaration("target")
  let wrapper =
    #|fn target(input : Input) -> Output {
    #|  target_helper(input)
    #|}
  let new_source = wrapper + "\n" + long_free_declaration("target_helper")
  @debug.assert_eq(
    align_impl_units_by_key(parse_units(old_source), parse_units(new_source)).map(
      edit_declaration_summary,
    ),
    ["Delete(other)", "Replace(target->target_helper)", "Insert(target)"],
  )
}

///|
test "fuzzy alignment pairs a renamed method beside a stable anchor" {
  let old_source =
    #|fn stable() {}
    #|fn JobHandle::spawn_unix(path : String) {
    #|  launch(path)
    #|}
  let new_source =
    #|fn stable() {}
    #|fn JobHandle::spawn_unix_ffi(path : String) {
    #|  launch(path)
    #|}
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Replace(2->2)",
  ])
}

///|
test "fuzzy alignment uniquely pairs several changes under one receiver" {
  let old_source =
    #|fn stable() {}
    #|fn Worker::read_unix(path : String) { read(path) }
    #|fn Worker::write_unix(path : String) { write(path) }
  let new_source =
    #|fn stable() {}
    #|fn Worker::read_unix_ffi(path : String) { read(path) }
    #|fn Worker::write_unix_ffi(path : String) { write(path) }
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Replace(2->2)", "Replace(3->3)",
  ])
}

///|
test "fuzzy alignment rejects tied best candidates" {
  let old_source =
    #|fn stable() {}
    #|fn Worker::old_name() { body() }
  let new_source =
    #|fn stable() {}
    #|fn Worker::new_name() { body() }
    #|fn Worker::new_name() { body() }
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Delete(2)", "Insert(2)", "Insert(3)",
  ])
}

///|
test "fuzzy alignment keeps a split helper as delete and inserts" {
  let old_source =
    #|fn inspect_parse(input : String, expected : String) -> Unit raise {
    #|  match parse_program(input) {
    #|    Ok(exprs) => inspect(exprs[0], content=expected)
    #|    Err(diagnostic) => inspect(diagnostic, content=expected)
    #|  }
    #|}
    #|fn stable() {}
  let new_source =
    #|fn expect_parse_ok(input : String, expected : String) -> Unit raise {
    #|  match parse_program(input) {
    #|    Ok(exprs) => if exprs.is_empty() { abort("empty") } else { inspect(exprs[0], content=expected) }
    #|    Err(diagnostic) => abort("unexpected diagnostic")
    #|  }
    #|}
    #|fn expect_parse_err(input : String, expected : String) -> Unit raise {
    #|  match parse_program(input) {
    #|    Ok(_) => abort("expected diagnostic")
    #|    Err(diagnostic) => inspect(diagnostic, content=expected)
    #|  }
    #|}
    #|fn stable() {}
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  assert_true(
    edits is [Delete(_), Replace(..), Insert(_), Insert(_)],
    msg=edits.map(edit_line_summary).join(", "),
  )
}

///|
test "fuzzy alignment does not cross receivers or reference ownership" {
  let cases = [
    (
      "fn stable() {}\nfn First::run_unix() { body() }", "fn stable() {}\nfn Second::run_unix_ffi() { body() }",
    ),
    (
      "fn stable() {}\nfn &Worker::run_unix() { body() }", "fn stable() {}\nfn Worker::run_unix_ffi() { body() }",
    ),
  ]
  for sources in cases {
    let (old_source, new_source) = sources
    let edits = align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
    )
    @debug.assert_eq(edits.map(edit_line_summary), [
      "Replace(1->1)", "Delete(2)", "Insert(2)",
    ])
  }
}

///|
test "fuzzy impl methods include receiver and trait in their owner" {
  let units = parse_units("impl Eq for Worker with equal(self, other) { true }")
  guard units is [{ fuzzy: Some(info), .. }] else {
    fail("expected impl-method fuzzy metadata")
  }
  assert_eq(info.name, "equal")
  assert_eq(info.owner, "impl:Worker:Eq")

  let edits = align_impl_units_by_key(
    parse_units(
      "fn stable() {}\nimpl Eq for Worker with equal_old(self, other) { true }",
    ),
    parse_units(
      "fn stable() {}\nimpl Ord for Worker with equal_new(self, other) { true }",
    ),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Delete(2)", "Insert(2)",
  ])
}

///|
test "fuzzy alignment stays inside gaps between reliable anchors" {
  let old_source =
    #|fn Worker::run_unix() { body() }
    #|fn stable() {}
  let new_source =
    #|fn stable() {}
    #|fn Worker::run_unix_ffi() { body() }
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Delete(1)", "Replace(2->1)", "Insert(2)",
  ])
}

///|
test "fuzzy alignment supports free functions and exact type declaration kinds" {
  let old_source =
    #|fn stable() {}
    #|fn parse_config(text : String) -> Int { parse(text) }
    #|struct ConfigRecord { value : Int }
  let new_source =
    #|fn stable() {}
    #|fn parse_configuration(text : String) -> Int { parse(text) }
    #|struct ConfigurationRecord { value : Int }
  let edits = align_impl_units_by_key(
    parse_units(old_source),
    parse_units(new_source),
  )
  @debug.assert_eq(edits.map(edit_line_summary), [
    "Replace(1->1)", "Replace(2->2)", "Replace(3->3)",
  ])

  let incompatible = align_impl_units_by_key(
    parse_units("fn stable() {}\nstruct Shape { value : Int }"),
    parse_units("fn stable() {}\nenum ShapeKind { Value(Int) }"),
  )
  @debug.assert_eq(incompatible.map(edit_line_summary), [
    "Replace(1->1)", "Delete(2)", "Insert(2)",
  ])
}

///|
test "UUID anchors keep priority and conflicting UUIDs forbid fuzzy pairing" {
  let same_uuid_old =
    #|fn stable() {}
    #|///|UUID(target-id)
    #|fn Worker::old_name() { old_body() }
  let same_uuid_new =
    #|fn stable() {}
    #|///|UUID(target-id)
    #|fn Worker::completely_different() { new_body() }
  @debug.assert_eq(
    align_impl_units_by_key(
      parse_units(same_uuid_old),
      parse_units(same_uuid_new),
    ).map(edit_line_summary),
    ["Replace(1->1)", "Replace(2->2)"],
  )

  let old_source =
    #|fn stable() {}
    #|///|UUID(old-id)
    #|fn Worker::run_unix() { body() }
  let new_source =
    #|fn stable() {}
    #|///|UUID(new-id)
    #|fn Worker::run_unix_ffi() { body() }
  @debug.assert_eq(
    align_impl_units_by_key(parse_units(old_source), parse_units(new_source)).map(
      edit_line_summary,
    ),
    ["Replace(1->1)", "Delete(2)", "Insert(2)"],
  )
  @debug.assert_eq(
    align_impl_units_by_key(
      parse_units(old_source),
      parse_units(new_source),
      use_uuid=false,
    ).map(edit_line_summary),
    ["Replace(1->1)", "Replace(2->2)"],
  )
}

///|
fn diff_document_for_test(
  old_source : String,
  new_source : String,
  mode : AlignedDiffMode,
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> DetailedDiffResult {
  diff_document_detailed(
    old_source,
    new_source,
    context~,
    graph_limit~,
    ignore_comments~,
    ignore_tests~,
    mode~,
  )
}

///|
fn section_fragment(section : @model.DiffSection) -> @model.DiffFragment {
  match section {
    Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
  }
}

///|
fn result_fragments(result : DetailedDiffResult) -> Array[@model.DiffFragment] {
  match result.document {
    Whole(fragment) => [fragment]
    TopLevel(top) => top.sections.map(section_fragment)
  }
}

///|
fn result_is_empty(result : DetailedDiffResult) -> Bool {
  result_fragments(result).all(fragment => fragment.document.hunks.is_empty())
}

///|
fn result_fallbacks(result : DetailedDiffResult) -> Array[FallbackReason] {
  let reasons : Array[FallbackReason] = []
  for fragment in result_fragments(result) {
    reasons.push_iter(fragment.fallbacks.iter())
  }
  reasons
}

///|
fn first_changed_document(result : DetailedDiffResult) -> @model.HunkDocument {
  for fragment in result_fragments(result) {
    if !fragment.document.hunks.is_empty() {
      return fragment.document
    }
  }
  { hunks: [], }
}

///|
test "renamed declarations render one paired hunk in lexical and AST modes" {
  let old_source =
    #|fn stable() {}
    #|fn JobHandle::spawn_unix(path : String) {
    #|  launch(path)
    #|}
  let new_source =
    #|fn stable() {}
    #|fn JobHandle::spawn_unix_ffi(path : String) {
    #|  launch(path)
    #|}
  for mode in [Lexical, Ast] {
    let result = diff_document_for_test(old_source, new_source, mode, context=0)
    assert_true(result.status is Changed)
    assert_true(result_fallbacks(result).is_empty())
    let document = first_changed_document(result)
    assert_eq(document.hunks.length(), 1)
    let patch = @unified.render_unified_hunks(document).join("")
    assert_true(patch.contains("spawn_unix"), msg=patch)
    assert_true(patch.contains("spawn_unix_ffi"), msg=patch)
  }
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
  @diff.mark_syntax_roots_with_budget(
    lhs_roots,
    rhs_roots,
    change_map,
    3_000_000,
    alignment_test_budget(),
  ) catch {
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
fn changed_segment_text(document : @model.HunkDocument) -> String {
  let buf = StringBuilder()
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
  segments : ArrayView[@model.DiffSegment],
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
      ast_line_segments_impl("left right", Some([(1, 5), (6, 11)])),
    ),
    ["changed:left right"],
  )

  @debug.assert_eq(
    ast_segment_summary(
      ast_line_segments_impl("left\tright", Some([(1, 5), (6, 11)])),
    ),
    ["changed:left\tright"],
  )

  @debug.assert_eq(
    ast_segment_summary(
      ast_line_segments_impl("  left \t right  ", Some([(3, 7), (10, 15)])),
    ),
    ["unchanged:  ", "changed:left \t right", "unchanged:  "],
  )

  @debug.assert_eq(
    ast_segment_summary(
      ast_line_segments_impl("left, right", Some([(1, 5), (7, 12)])),
    ),
    ["changed:left", "unchanged:, ", "changed:right"],
  )

  @debug.assert_eq(
    ast_segment_summary(ast_line_segments_impl("  unchanged  ", None)),
    ["unchanged:  unchanged  "],
  )
}

///|
fn top_level_for_test(result : DetailedDiffResult) -> @model.TopLevelDiff raise {
  guard result.document is TopLevel(top) else {
    fail("expected a top-level semantic document")
  }
  top
}

///|
fn whole_fragment_for_test(
  result : DetailedDiffResult,
) -> @model.DiffFragment raise {
  guard result.document is Whole(fragment) else {
    fail("expected a whole semantic document")
  }
  fragment
}

///|
fn semantic_changed_text(result : DetailedDiffResult) -> String {
  let buf = StringBuilder()
  for fragment in result_fragments(result) {
    buf.write_string(changed_segment_text(fragment.document))
  }
  buf.to_string()
}

///|
fn assert_fragment_bounds(
  fragment : @model.DiffFragment,
  old_len : Int?,
  new_len : Int?,
) -> Unit raise {
  for hunk in fragment.document.hunks {
    if old_len is Some(limit) {
      assert_true(hunk.old_start >= 0)
      assert_true(hunk.old_start + hunk.old_len <= limit)
    }
    if new_len is Some(limit) {
      assert_true(hunk.new_start >= 0)
      assert_true(hunk.new_start + hunk.new_len <= limit)
    }
  }
}

///|
test "sectioned lexical changes include their complete declaration ranges" {
  let old_source =
    #|fn unchanged_before() {}
    #|
    #|/// target docs
    #|fn target() {
    #|  stable_prefix_one()
    #|  stable_prefix_two()
    #|  stable_prefix_three()
    #|  stable_prefix_four()
    #|  old_head()
    #|  stable_one()
    #|  stable_two()
    #|
    #|  stable_three()
    #|  stable_four()
    #|  old_tail()
    #|  stable_suffix_one()
    #|  stable_suffix_two()
    #|  stable_suffix_three()
    #|  stable_suffix_four()
    #|}
    #|
    #|fn unchanged_after() {}
  let new_source =
    #|fn unchanged_before() {}
    #|
    #|/// target docs
    #|fn target() {
    #|  stable_prefix_one()
    #|  stable_prefix_two()
    #|  stable_prefix_three()
    #|  stable_prefix_four()
    #|  new_head()
    #|  stable_one()
    #|  stable_two()
    #|
    #|  stable_three()
    #|  stable_four()
    #|  new_tail()
    #|  stable_suffix_one()
    #|  stable_suffix_two()
    #|  stable_suffix_three()
    #|  stable_suffix_four()
    #|}
    #|
    #|fn unchanged_after() {}
  for context in [0, 3] {
    let result = diff_document_for_test(
      old_source,
      new_source,
      Lexical,
      context~,
    )
    let top = top_level_for_test(result)
    guard top.sections
      is [
        Matched(diff=leading, ..),
        Matched(old=old_range, new=new_range, diff=target, ..),
        Matched(diff=trailing, ..),
      ] else {
      fail("expected one changed declaration between stable neighbors")
    }
    assert_true(leading.document.hunks.is_empty())
    assert_true(trailing.document.hunks.is_empty())
    guard target.document.hunks is [hunk] else {
      fail("expected one complete declaration hunk")
    }
    assert_eq(hunk.old_start, 0)
    assert_eq(hunk.old_len, old_range.len)
    assert_eq(hunk.new_start, 0)
    assert_eq(hunk.new_len, new_range.len)
    let patch = @unified.render_unified_hunks(target.document).join("")
    for
      text in [
        "/// target docs", "fn target() {", "stable_prefix_one()", "stable_one()",
        "stable_four()", "old_tail()", "new_tail()", "stable_suffix_four()", "}",
      ] {
      assert_true(patch.contains(text), msg=patch)
    }
    assert_false(patch.contains("unchanged_before"), msg=patch)
    assert_false(patch.contains("unchanged_after"), msg=patch)
  }
}

///|
test "complete lexical sections restore filtered trivia and fill inserts and deletes" {
  let old_source =
    #|test "sample" { old_test() }
    #|
    #|/// old production docs
    #|///|UUID(old-production-marker)
    #|fn production() {
    #|  let value = old_value()
    #|
    #|  // old production note
    #|  value
    #|}
  let new_source =
    #|test "sample" { new_test() }
    #|
    #|/// new production docs
    #|///|UUID(new-production-marker)
    #|fn production() {
    #|  let value = new_value()
    #|
    #|  // new production note
    #|  value
    #|}
  let filtered = diff_document_for_test(
    old_source,
    new_source,
    Lexical,
    context=0,
    ignore_comments=true,
    ignore_tests=true,
  )
  guard top_level_for_test(filtered).sections
    is [Matched(old=old_range, new=new_range, diff=fragment, ..)] else {
    fail("expected only the changed production declaration")
  }
  guard fragment.document.hunks is [hunk] else {
    fail("expected one restored production hunk")
  }
  assert_eq(hunk.old_start, 0)
  assert_eq(hunk.old_len, old_range.len)
  assert_eq(hunk.new_start, 0)
  assert_eq(hunk.new_len, new_range.len)
  let patch = @unified.render_unified_hunks(fragment.document).join("")
  for
    text in [
      "/// old production docs", "/// new production docs", "///|UUID(old-production-marker)",
      "///|UUID(new-production-marker)", "// old production note", "// new production note",
      "old_value()", "new_value()",
    ] {
    assert_true(patch.contains(text), msg=patch)
  }
  assert_true(patch.contains("\n \n"), msg=patch)
  assert_false(patch.contains("old_test"), msg=patch)
  assert_false(patch.contains("new_test"), msg=patch)
  let changed = changed_segment_text(fragment.document)
  assert_true(changed.contains("old_value"), msg=changed)
  assert_true(changed.contains("new_value"), msg=changed)
  assert_false(changed.contains("production docs"), msg=changed)
  assert_false(changed.contains("production note"), msg=changed)
  assert_false(changed.contains("UUID"), msg=changed)

  let inserted = diff_document_for_test(
    "fn keep() {}",
    "fn keep() {}\n\n/// inserted docs\nfn inserted() {\n  first()\n  last()\n}",
    Lexical,
    context=0,
  )
  guard top_level_for_test(inserted).sections
    is [Matched(diff=keep, ..), Inserted(new=inserted_range, diff=added, ..)] else {
    fail("expected one stable and one inserted declaration")
  }
  assert_true(keep.document.hunks.is_empty())
  guard added.document.hunks is [added_hunk] else {
    fail("expected one inserted declaration hunk")
  }
  assert_eq(added_hunk.new_start, 0)
  assert_eq(added_hunk.new_len, inserted_range.len)

  let deleted = diff_document_for_test(
    "fn keep() {}\n\n/// deleted docs\nfn deleted() {\n  first()\n  last()\n}",
    "fn keep() {}",
    Lexical,
    context=0,
  )
  guard top_level_for_test(deleted).sections
    is [Matched(diff=kept, ..), Deleted(old=deleted_range, diff=removed, ..)] else {
    fail("expected one stable and one deleted declaration")
  }
  assert_true(kept.document.hunks.is_empty())
  guard removed.document.hunks is [removed_hunk] else {
    fail("expected one deleted declaration hunk")
  }
  assert_eq(removed_hunk.old_start, 0)
  assert_eq(removed_hunk.old_len, deleted_range.len)
}

///|
test "Whole and AST lexical fallbacks retain compact caller context" {
  let old_source =
    #|fn stable() {}
    #|fn target() {
    #|  stable_zero()
    #|  stable_one()
    #|  old_value()
    #|  stable_three()
    #|  stable_four()
    #|}
  let new_source =
    #|fn stable() {}
    #|fn target() {
    #|  stable_zero()
    #|  stable_one()
    #|  new_value()
    #|  stable_three()
    #|  stable_four()
    #|}
  let structural = diff_document_for_test(
    old_source,
    new_source,
    Ast,
    context=0,
  )
  guard top_level_for_test(structural).sections
    is [Matched(diff=stable, ..), Matched(old=structural_range, diff=ast, ..)] else {
    fail("expected a changed AST declaration")
  }
  assert_true(stable.document.hunks.is_empty())
  guard ast.document.hunks is [ast_hunk] else {
    fail("expected one compact AST hunk")
  }
  assert_true(ast_hunk.old_start > 0)
  assert_true(ast_hunk.old_len < structural_range.len)

  let local_fallback = diff_document_for_test(
    old_source,
    new_source,
    Ast,
    context=0,
    graph_limit=0,
  )
  guard top_level_for_test(local_fallback).sections
    is [
      Matched(diff=unchanged, ..),
      Matched(old=fallback_range, diff=fallback, ..),
    ] else {
    fail("expected a section-local graph fallback")
  }
  assert_true(unchanged.document.hunks.is_empty())
  assert_true(fallback.fallbacks is [GraphLimitExceeded(limit=0)])
  guard fallback.document.hunks is [fallback_hunk] else {
    fail("expected one compact lexical fallback hunk")
  }
  assert_true(fallback_hunk.old_start > 0)
  assert_true(fallback_hunk.old_len < fallback_range.len)

  let parse_old =
    #|fn broken( {
    #|  stable_zero()
    #|  stable_one()
    #|  old_value()
    #|  stable_three()
    #|}
  let parse_new =
    #|fn broken( {
    #|  stable_zero()
    #|  stable_one()
    #|  new_value()
    #|  stable_three()
    #|}
  let parsed = diff_document_for_test(parse_old, parse_new, Lexical, context=0)
  guard parsed.document is Whole(parsed_fragment) else {
    fail("expected a Whole parse fallback")
  }
  assert_true(parsed_fragment.fallbacks is [ParseError(..)])
  guard parsed_fragment.document.hunks is [parsed_hunk] else {
    fail("expected one compact parse fallback hunk")
  }
  assert_true(parsed_hunk.old_start > 0)
  assert_true(parsed_hunk.old_len < 6)

  let root = diff_document_for_test(
    "fn old_root() {\n  stable_zero()\n  stable_one()\n  stable_two()\n}",
    "fn new_root() {\n  stable_zero()\n  stable_one()\n  stable_two()\n}",
    Lexical,
    context=0,
  )
  guard root.document is Whole(root_fragment) else {
    fail("expected a Whole RootList lexical document")
  }
  assert_true(root_fragment.fallbacks.is_empty())
  guard root_fragment.document.hunks is [root_hunk] else {
    fail("expected one compact RootList hunk")
  }
  assert_true(root_hunk.old_len < 5)

  let limit_old =
    #|fn stable() {}
    #|fn Worker::old_name() {
    #|  stable_zero()
    #|  stable_one()
    #|  stable_two()
    #|  stable_three()
    #|}
  let limit_new =
    #|fn stable() {}
    #|fn Worker::new_name() {
    #|  stable_zero()
    #|  stable_one()
    #|  stable_two()
    #|  stable_three()
    #|}
  let limited = calculate_diff_document_with_limit(
    limit_old, limit_new, "old", "new", 0, 3_000_000, false, 0,
  )
  guard limited.document is Whole(limited_fragment) else {
    fail("expected a Whole computation-limit fallback")
  }
  assert_true(
    limited_fragment.fallbacks
    is [ComputationLimitExceeded(stage=TopLevelAlignment, limit=0)],
  )
  guard limited_fragment.document.hunks is [limited_hunk] else {
    fail("expected one compact computation fallback hunk")
  }
  assert_true(limited_hunk.old_start > 0)
  assert_true(limited_hunk.old_len < 7)
}

///|
test "top-level plan preserves crossing declaration identities and both orders" {
  let old_units = parse_units("fn first() {}\nfn second() {}")
  let new_units = parse_units("fn second() {}\nfn first() {}")
  guard top_level_plan_impl(old_units, new_units, alignment_test_budget())
    is PerUnit(plan) else {
    fail("expected reliable semantic pairs")
  }
  @debug.assert_eq(plan.edits.map(edit_line_summary), [
    "Replace(1->2)", "Replace(2->1)",
  ])
  assert_true(plan.old_order is [0, 1])
  assert_true(plan.new_order is [1, 0])
  assert_true(plan.reordered)

  let unmatched_old = parse_units("/// trailing old")
  let unmatched_new = parse_units("/// trailing new")
  assert_true(
    top_level_plan_impl(unmatched_old, unmatched_new, alignment_test_budget())
    is RootList(..),
  )
}

///|
test "implementation unit ranges are exact across universal newlines" {
  for
    source in [
      "fn first() {}\nfn second() {}", "fn first() {}\r\nfn second() {}\r\n", "fn first() {}\rfn second() {}",
    ] {
    let units = parse_units(source)
    assert_eq(units.length(), 2)
    assert_true(units[0].range == @model.LineRange::{ start: 0, len: 1, })
    assert_true(units[1].range == @model.LineRange::{ start: 1, len: 1, })
  }

  let documented = parse_units(
    "/// docs\nfn first() {}\n\n/// next\nfn second() {}\n",
  )
  assert_true(documented[0].range == @model.LineRange::{ start: 0, len: 2, })
  assert_true(documented[1].range == @model.LineRange::{ start: 3, len: 2, })
}

///|
test "section fragments use local coordinates and exact source ranges" {
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
  for mode in [Lexical, Ast] {
    let result = diff_document_for_test(old_source, new_source, mode, context=0)
    assert_true(result.status is Changed)
    let top = top_level_for_test(result)
    assert_false(top.reordered)
    assert_true(top.old_order is [0, 1])
    assert_true(top.new_order is [2, 0, 1])
    assert_eq(top.sections.length(), 3)
    guard top.sections
      is [
        Matched(
          old={ start: 0, len: 1, },
          new={ start: 1, len: 1, },
          diff=keep,
          ..
        ),
        Matched(
          old={ start: 1, len: 3, },
          new={ start: 2, len: 3, },
          diff=target,
          ..
        ),
        Inserted(new={ start: 0, len: 1, }, diff=inserted, ..),
      ] else {
      fail("expected matched declarations plus one new-side section")
    }
    assert_true(keep.document.hunks.is_empty())
    assert_fragment_bounds(target, Some(3), Some(3))
    assert_fragment_bounds(inserted, None, Some(1))
    assert_false(target.document.hunks.is_empty())
    assert_false(inserted.document.hunks.is_empty())
    assert_true(result_fallbacks(result).is_empty())
  }
}

///|
test "pure top-level reorder is semantic instead of lexical fallback" {
  for mode in [Lexical, Ast] {
    let result = diff_document_for_test(
      "fn first() {}\nfn second() {}",
      "fn second() {}\nfn first() {}",
      mode,
      context=0,
    )
    assert_true(result.status is Reordered)
    let top = top_level_for_test(result)
    assert_true(top.reordered)
    assert_true(top.old_order is [0, 1])
    assert_true(top.new_order is [1, 0])
    assert_eq(top.sections.length(), 2)
    assert_true(result_is_empty(result))
    assert_true(result_fallbacks(result).is_empty())
  }
}

///|
test "reorder plus an internal change remains Changed" {
  let result = diff_document_for_test(
    "fn first() { old_value() }\nfn second() {}",
    "fn second() {}\nfn first() { new_value() }",
    Ast,
    context=0,
  )
  assert_true(result.status is Changed)
  let top = top_level_for_test(result)
  assert_true(top.reordered)
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [1, 0])
  let changed = semantic_changed_text(result)
  assert_true(changed.contains("old_value"), msg=changed)
  assert_true(changed.contains("new_value"), msg=changed)
}

///|
test "inserted and deleted declarations have no fabricated opposite range" {
  let inserted = diff_document_for_test(
    "fn keep() {}",
    "fn added() {}\nfn keep() {}",
    Ast,
    context=0,
  )
  let inserted_top = top_level_for_test(inserted)
  assert_true(inserted_top.old_order is [0])
  assert_true(inserted_top.new_order is [1, 0])
  guard inserted_top.sections
    is [Matched(..), Inserted(new={ start: 0, len: 1, }, diff~, ..)] else {
    fail("expected a distinct inserted section")
  }
  assert_fragment_bounds(diff, None, Some(1))

  let deleted = diff_document_for_test(
    "fn removed() {}\nfn keep() {}",
    "fn keep() {}",
    Ast,
    context=0,
  )
  let deleted_top = top_level_for_test(deleted)
  assert_true(deleted_top.old_order is [0, 1])
  assert_true(deleted_top.new_order is [1])
  guard deleted_top.sections
    is [Deleted(old={ start: 0, len: 1, }, diff~, ..), Matched(..)] else {
    fail("expected a distinct deleted section")
  }
  assert_fragment_bounds(diff, Some(1), None)
}

///|
test "formatting-only AST changes retain an empty matched section" {
  let result = diff_document_for_test(
    "fn format() { 1 }",
    "fn format() {\n  1\n}",
    Ast,
  )
  assert_true(result.status is NoStructuralChanges)
  let top = top_level_for_test(result)
  guard top.sections is [Matched(diff~, ..)] else {
    fail("expected one reliable matched section")
  }
  assert_true(diff.document.hunks.is_empty())
  assert_false(top.reordered)
}

///|
test "parse and root-list fallbacks attach only to Whole fragments" {
  let parsed = calculate_diff_document(
    "fn broken( {",
    "fn okay() {}",
    old_name="before.mbt",
    new_name="after.mbt",
    context=0,
  )
  assert_true(parsed.status is Changed)
  let parsed_fragment = whole_fragment_for_test(parsed)
  guard parsed_fragment.fallbacks is [ParseError(sides=[Old], detail~)] else {
    fail("expected an old-side parse fallback")
  }
  assert_true(detail.contains("before.mbt"), msg=detail)
  assert_false(parsed_fragment.document.hunks.is_empty())

  let root = diff_document_for_test(
    "/// trailing old",
    "/// trailing new",
    Ast,
    context=0,
    graph_limit=0,
  )
  let root_fragment = whole_fragment_for_test(root)
  assert_true(root_fragment.fallbacks is [GraphLimitExceeded(limit=0)])
  assert_false(root_fragment.document.hunks.is_empty())
}

///|
test "top-level budget exhaustion creates one Whole fallback" {
  let result = calculate_diff_document_with_limit(
    "fn stable() {}\nfn Worker::old_name() { body() }", "fn stable() {}\nfn Worker::new_name() { body() }",
    "old", "new", 0, 3_000_000, false, 0,
  )
  let fragment = whole_fragment_for_test(result)
  assert_true(
    fragment.fallbacks
    is [ComputationLimitExceeded(stage=TopLevelAlignment, limit=0)],
  )
  assert_false(fragment.document.hunks.is_empty())
}

///|
test "local fallbacks stay on their own top-level fragments" {
  let old_source =
    #|///|UUID(first)
    #|fn first() { "alpha beta gamma" }
    #|///|UUID(second)
    #|fn second() { "one two three" }
  let new_source =
    #|///|UUID(first)
    #|fn first() { "alpha zeta gamma" }
    #|///|UUID(second)
    #|fn second() { "one four three" }
  let graph = diff_document_for_test(
    old_source,
    new_source,
    Ast,
    context=0,
    graph_limit=0,
  )
  let graph_top = top_level_for_test(graph)
  assert_eq(graph_top.sections.length(), 2)
  for section in graph_top.sections {
    let fragment = section_fragment(section)
    assert_true(fragment.fallbacks is [GraphLimitExceeded(limit=0)])
    assert_false(fragment.document.hunks.is_empty())
  }

  let limited = calculate_diff_document_with_limit(
    old_source, new_source, "old", "new", 0, 3_000_000, false, 0,
  )
  let limited_top = top_level_for_test(limited)
  assert_eq(limited_top.sections.length(), 2)
  for section in limited_top.sections {
    let fragment = section_fragment(section)
    assert_true(fragment.fallbacks is [ComputationLimitExceeded(limit=0, ..)])
  }
}

///|
test "comment and test filters preserve semantic statuses in both modes" {
  let comment_old = "fn value() { 1 // old\n}"
  let comment_new = "fn value() { 1 // new\n}"
  let test_old = "test \"sample\" { old_test() }"
  let test_new = "test \"sample\" { new_test() }"
  for mode in [Lexical, Ast] {
    let comments = diff_document_for_test(
      comment_old,
      comment_new,
      mode,
      ignore_comments=true,
    )
    assert_true(comments.status is IgnoredOnly)
    assert_true(result_is_empty(comments))

    let tests = diff_document_for_test(
      test_old,
      test_new,
      mode,
      ignore_tests=true,
    )
    assert_true(tests.status is IgnoredOnly)
    assert_true(result_is_empty(tests))
  }
}

///|
test "filtered local fragments retain production changes only" {
  let result = diff_document_for_test(
    "/// old docs\nfn production() { old_value() }\ntest \"t\" { old_test() }",
    "/// new docs\nfn production() { new_value() }\ntest \"t\" { new_test() }",
    Ast,
    context=0,
    ignore_comments=true,
    ignore_tests=true,
  )
  assert_true(result.status is Changed)
  let changed = semantic_changed_text(result)
  assert_true(changed.contains("old_value"), msg=changed)
  assert_true(changed.contains("new_value"), msg=changed)
  assert_false(changed.contains("old_test"), msg=changed)
  assert_false(changed.contains("new_test"), msg=changed)
  assert_true(result_fallbacks(result).is_empty())
}

///|
test "identical, blank-only, and universal-newline results keep status priority" {
  let identical = diff_document_for_test("fn same() {}", "fn same() {}", Ast)
  assert_true(identical.status is Identical)
  assert_true(identical.document is Whole(_))
  assert_true(result_is_empty(identical))

  let blank = diff_document_for_test(
    "fn same() {}\n",
    "fn same() {}\n\n \n",
    Ast,
    ignore_comments=true,
  )
  assert_true(blank.status is IgnoredOnly)
  assert_true(result_is_empty(blank))

  for
    sources in [
      ("fn f() {\n  1\n}", "fn f() {\n  2\n}"),
      ("fn f() {\r\n  1\r\n}", "fn f() {\r\n  2\r\n}"),
      ("fn f() {\r  1\r}", "fn f() {\r  2\r}"),
    ] {
    let (old_source, new_source) = sources
    let result = diff_document_for_test(old_source, new_source, Ast)
    assert_true(result.status is Changed)
    assert_false(result_is_empty(result))
  }
}

///|
test "lexical RootList remains a primary Whole document" {
  let result = diff_document_for_test(
    "/// trailing old",
    "/// trailing new",
    Lexical,
    context=0,
  )
  assert_true(result.status is Changed)
  let fragment = whole_fragment_for_test(result)
  assert_true(fragment.fallbacks.is_empty())
  assert_false(fragment.document.hunks.is_empty())
}
