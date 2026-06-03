///|UUID(65d38778-101d-4c7e-8ee6-803711f6a4f6)
fn test_span(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> @span.SingleLineSpan {
  @span.SingleLineSpan::{ line, start_col, end_col }
}

///|UUID(e501c2b7-6c26-4f4b-81da-20dafcb87266)
fn test_string_atom(content : String) -> Syntax {
  Syntax::atom(
    content~,
    position=[test_span(1, 1, content.length() + 3)],
    kind=AtomKind::String(StringKind::StringLiteral),
  )
}

///|UUID(81d3736c-9a4e-4d96-8603-9c86d8f41c74)
fn novel_width(positions : ArrayView[MatchedPos]) -> Int {
  let width = Ref(0)
  for position in positions {
    if position.kind.is_novel() {
      width.val += position.pos.end_col - position.pos.start_col
    }
  }
  width.val
}

///|UUID(9d90653e-b585-4962-93b3-46e6e0ad7796)
test "change_positions narrows replaced string to changed word" {
  let lhs = test_string_atom("alpha beta gamma")
  let rhs = test_string_atom("alpha zeta gamma")
  init_all_info([lhs], [rhs])

  let change_map = ChangeMap::new()
  change_map.insert(rhs, ChangeKind::ReplacedString(lhs~, rhs~))
  let positions = change_positions([rhs], change_map)

  assert_true(positions.length() > 0)
  assert_true(novel_width(positions) > 0)
  assert_true(novel_width(positions) < "alpha zeta gamma".length())
}
