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

///|UUID(1bfc1fdd-7d6e-45d9-9a3d-12672bcd26bd)
fn parse_units(source : String) -> Array[ImplUnit] {
  let (impls, reports) = @parser.parse_string(source)
  if reports.length() != 0 {
    panic()
  }
  collect_impl_units(source, impls)
}

///|UUID(0c6b3f16-db94-47b3-a98d-6703cfaa9863)
test "align_impl_units_by_uuid aligns top-level UUID blocks before inner AST diff" {
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

///|UUID(5899396d-f317-4aa3-bdae-68ae6ff257e5)
test "empty delimiter wrappers do not hide inserted sibling statements" {
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

  let lhs_block = match lhs_roots[0] {
    @syntax.Syntax::List(children~, ..) => children[1]
    _ => panic()
  }
  let lhs_stmt_wrapper = match lhs_block {
    @syntax.Syntax::List(children~, ..) => children[0]
    _ => panic()
  }
  let rhs_block = match rhs_roots[0] {
    @syntax.Syntax::List(children~, ..) => children[1]
    _ => panic()
  }
  let rhs_inserted_stmt = match rhs_block {
    @syntax.Syntax::List(children~, ..) => children[1]
    _ => panic()
  }

  assert_true(
    change_map.get(rhs_inserted_stmt) is Some(@syntax.ChangeKind::Novel),
  )
  match change_map.get(lhs_stmt_wrapper) {
    Some(@syntax.ChangeKind::Unchanged(opposite)) =>
      @debug.assert_eq(opposite.content_id(), lhs_stmt_wrapper.content_id())
    _ => panic()
  }
}
