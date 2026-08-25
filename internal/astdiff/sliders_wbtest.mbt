///|
fn slider_test_list(kind : @cst.NodeKind, children : Array[Syntax]) -> Syntax {
  Syntax::list(
    open_content="(",
    open_position=[],
    children~,
    close_content=")",
    close_position=[],
    kind=@syntax.ListKind::from_node_kind(kind),
  )
}

///|
fn slider_test_kind(source : String) -> @cst.NodeKind raise {
  let result = @cst.parse_structure(source)
  assert_true(result.diagnostics_view().is_empty())
  for entry in result.root().children {
    let (label, child) = entry
    if label == Some("item") {
      return child.kind
    }
  }
  fail("expected one CST item")
}

///|
test "nested slider does not push unchanged to ancestor of another ListKind" {
  let function_kind = slider_test_kind("fn f() {}")
  let let_kind = slider_test_kind("let value = 1")
  let inner = slider_test_list(let_kind, [])
  let root = slider_test_list(function_kind, [inner])
  let opposite = slider_test_list(let_kind, [])
  @syntax.init_all_info([root], [opposite])
  let change_map = ChangeMap::new()
  change_map.insert(root, Novel)
  change_map.insert(inner, Unchanged(opposite))

  push_unchanged_to_ancestor(root, inner, change_map)

  assert_true(change_map.get(root) is Some(Novel))
  assert_true(change_map.get(inner) is Some(Unchanged(_)))
}

///|
test "nested slider does not push unchanged to descendant of another ListKind" {
  let function_kind = slider_test_kind("fn f() {}")
  let let_kind = slider_test_kind("let value = 1")
  let inner = slider_test_list(let_kind, [])
  let root = slider_test_list(function_kind, [inner])
  let opposite = slider_test_list(function_kind, [])
  @syntax.init_all_info([root], [opposite])
  let change_map = ChangeMap::new()
  change_map.insert(root, Unchanged(opposite))
  change_map.insert(inner, Novel)

  push_unchanged_to_descendant(root, inner, change_map)

  assert_true(change_map.get(root) is Some(Unchanged(_)))
  assert_true(change_map.get(inner) is Some(Novel))
}
