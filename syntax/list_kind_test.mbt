///|
using @syntax {type ListKind, type Syntax}

///|
fn list_kind(kind : @cst.NodeKind) -> ListKind {
  ListKind::from_node_kind(kind)
}

///|
fn parsed_item(source : String) -> @cst.CstNode raise {
  let result = @cst.parse_structure(source)
  assert_true(result.diagnostics_view().is_empty())
  for entry in result.root().children {
    let (label, child) = entry
    if label == Some("item") {
      return child
    }
  }
  fail("expected one CST item")
}

///|
fn list_kind_test_atom() -> Syntax {
  Syntax::atom(content="item", position=[], kind=@syntax.AtomKind::Normal)
}

///|
fn list_with_kind(kind : @cst.NodeKind) -> Syntax {
  Syntax::list(
    open_content="(",
    open_position=[],
    children=[list_kind_test_atom()],
    close_content=")",
    close_position=[],
    kind=list_kind(kind),
  )
}

///|
test "ListKind preserves exact NodeKind equality" {
  let function_node = parsed_item("fn f { () }")
  let same_function_node = parsed_item("fn g { () }")
  let let_node = parsed_item("let value = 1")
  assert_true(function_node.kind is @cst.Impl_Function)
  assert_true(same_function_node.kind is @cst.Impl_Function)
  assert_true(let_node.kind is @cst.Impl_Let)
  let function_kind = list_kind(function_node.kind)
  let same_function_kind = list_kind(same_function_node.kind)
  let let_kind = list_kind(let_node.kind)
  assert_true(function_kind == same_function_kind)
  assert_false(function_kind == let_kind)
}

///|
test "list content identity includes exact ListKind" {
  let function_kind = parsed_item("fn f { () }").kind
  let same_function_kind = parsed_item("fn g { () }").kind
  let let_kind = parsed_item("let value = 1").kind
  let lhs = list_with_kind(function_kind)
  let rhs_same_kind = list_with_kind(same_function_kind)
  let rhs_different_kind = list_with_kind(let_kind)
  @syntax.init_all_info([lhs], [rhs_same_kind, rhs_different_kind])
  assert_eq(lhs.content_id(), rhs_same_kind.content_id())
  assert_true(lhs.content_id() != rhs_different_kind.content_id())
}

///|
test "only anonymous delimiter-free single-child lists collapse" {
  let function_kind = list_kind(parsed_item("fn f { () }").kind)
  let identified = Syntax::simple_list(
    open_position=[],
    children=[list_kind_test_atom()],
    close_position=[],
    kind=function_kind,
  )
  guard identified is Syntax::List(kind=Some(actual_kind), children~, ..) else {
    fail("expected a list with an explicit kind")
  }
  assert_true(actual_kind == function_kind)
  assert_eq(children.length(), 1)

  let anonymous = Syntax::simple_list(
    open_position=[],
    children=[list_kind_test_atom()],
    close_position=[],
  )
  guard anonymous is Syntax::Atom(content="item", ..) else {
    fail("expected an anonymous list to collapse to its only child")
  }
}
