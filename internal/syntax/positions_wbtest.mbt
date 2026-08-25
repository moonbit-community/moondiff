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
  let budget = @computation.Budget::new(@computation.default_limit())
  let positions = change_positions_with_budget([rhs], change_map, budget)

  assert_true(positions.length() > 0)
  assert_true(novel_width(positions) > 0)
  assert_true(novel_width(positions) < "alpha zeta gamma".length())
}

///|
test "relative content positions account for CRLF and CR terminators" {
  guard relative_region_positions(
      "alpha\r\nbeta",
      [test_span(1, 0, 5), test_span(2, 0, 4)],
      0,
      7,
      11,
    )
    is [crlf_span] else {
    fail("expected one CRLF-relative span")
  }
  assert_eq((crlf_span.line, crlf_span.start_col, crlf_span.end_col), (2, 0, 4))
  guard relative_region_positions(
      "alpha\rbeta",
      [test_span(1, 0, 5), test_span(2, 0, 4)],
      0,
      6,
      10,
    )
    is [cr_span] else {
    fail("expected one CR-relative span")
  }
  assert_eq((cr_span.line, cr_span.start_col, cr_span.end_col), (2, 0, 4))
}
