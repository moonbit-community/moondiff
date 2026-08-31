///|
fn fallback_test_span(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> @span.SingleLineSpan {
  { line, start_col, end_col, }
}

///|
fn fallback_test_novel(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> MatchedPos {
  { kind: Novel, pos: fallback_test_span(line, start_col, end_col), }
}

///|
fn fallback_test_unchanged(
  pos : @span.SingleLineSpan,
  opposite : @span.SingleLineSpan,
) -> MatchedPos {
  { kind: Unchanged(opposite_pos=[opposite]), pos, }
}

///|
fn mapped_out_of_bounds_sides(
  positions : ArrayView[MatchedPos],
  own : SourceView,
  opposite : SourceView,
  own_side : DiffSide,
  opposite_side : DiffSide,
) -> Array[DiffSide] {
  let sides : Array[DiffSide] = []
  ignore(
    map_matched_positions(
      positions, own, opposite, own_side, opposite_side, sides,
    ),
  )
  ordered_out_of_bounds_sides(sides)
}

///|
test "matched-position mapping reports primary and opposite sides" {
  let old = @diff_ignore.SourceView::from_lines(["old"])
  let new = @diff_ignore.SourceView::from_lines(["new"])
  let valid = fallback_test_span(1, 1, 4)
  let invalid_line = fallback_test_span(2, 1, 2)
  assert_true(
    mapped_out_of_bounds_sides(
      [fallback_test_novel(2, 1, 2)],
      old,
      new,
      Old,
      New,
    )
    is [Old],
  )
  assert_true(
    mapped_out_of_bounds_sides(
      [fallback_test_novel(2, 1, 2)],
      new,
      old,
      New,
      Old,
    )
    is [New],
  )
  assert_true(
    mapped_out_of_bounds_sides(
      [fallback_test_unchanged(valid, invalid_line)],
      old,
      new,
      Old,
      New,
    )
    is [New],
  )
  assert_true(
    mapped_out_of_bounds_sides(
      [fallback_test_unchanged(valid, invalid_line)],
      new,
      old,
      New,
      Old,
    )
    is [Old],
  )
  let filtered_old = @diff_ignore.SourceView::from_source(
    "// hidden",
    ignore_comments=true,
  )
  assert_true(
    mapped_out_of_bounds_sides(
      [fallback_test_unchanged(fallback_test_span(1, 1, 3), invalid_line)],
      filtered_old,
      new,
      Old,
      New,
    )
    is [New],
  )
}

///|
test "matched-position mapping drops filtered opposite spans" {
  let own = @diff_ignore.SourceView::from_lines(["kept"])
  let opposite = @diff_ignore.SourceView::from_source(
    "// hidden",
    ignore_comments=true,
  )
  let out_of_bounds_sides : Array[DiffSide] = []
  let mapped = map_matched_positions(
    [
      fallback_test_unchanged(
        fallback_test_span(1, 1, 5),
        fallback_test_span(1, 1, 3),
      ),
    ],
    own,
    opposite,
    Old,
    New,
    out_of_bounds_sides,
  )
  assert_true(out_of_bounds_sides.is_empty())
  guard mapped is [{ kind: Unchanged(opposite_pos=[]), pos, }] else {
    fail("expected the primary position with no mapped opposite positions")
  }
  assert_eq((pos.line, pos.start_col, pos.end_col), (1, 1, 5))
}

///|
fn expect_ast_position_sides(
  lhs : ArrayView[MatchedPos],
  rhs : ArrayView[MatchedPos],
  expected : ArrayView[DiffSide],
) -> Unit raise {
  guard ast_document_from_positions(["old"], ["new"], lhs, rhs, 0, true)
    is AstPositionsOutOfBounds(sides) else {
    fail("expected AST position validation to stop document construction")
  }
  assert_true(sides == expected)
}

///|
test "AST document validates primary and opposite positions before indexing" {
  let old_valid = fallback_test_span(1, 1, 4)
  let new_valid = fallback_test_span(1, 1, 4)
  let invalid_line = fallback_test_span(2, 1, 2)
  let invalid_columns = fallback_test_span(1, 1, 6)
  expect_ast_position_sides([fallback_test_novel(2, 1, 2)], [], [Old])
  expect_ast_position_sides([], [fallback_test_novel(2, 1, 2)], [New])
  expect_ast_position_sides(
    [fallback_test_unchanged(old_valid, invalid_line)],
    [],
    [New],
  )
  expect_ast_position_sides(
    [],
    [fallback_test_unchanged(new_valid, invalid_columns)],
    [Old],
  )
  expect_ast_position_sides(
    [fallback_test_novel(2, 1, 2)],
    [fallback_test_novel(2, 1, 2)],
    [Old, New],
  )

  guard ast_document_from_positions(
      ["old"],
      ["new"],
      [fallback_test_novel(1, 2, 2)],
      [],
      0,
      true,
    )
    is AstDocument(_) else {
    fail("valid zero-width syntax positions must not trigger fallback")
  }
}

///|
fn fallback_test_unit(
  source : String,
  start_line : Int,
  position_line : Int,
) -> ImplUnit {
  ImplUnit::{
    root: @syntax.Syntax::atom(
      content=source,
      position=[
        fallback_test_span(position_line, 1, source.to_array().length() + 1),
      ],
      kind=Normal,
    ),
    uuid: None,
    semantic_key: None,
    fuzzy: None,
    range: { start: start_line - 1, len: 1, },
    context: None,
  }
}

///|
fn fallback_test_limit() -> UInt {
  @computation.default_scope_limit()
}

///|
fn fallback_test_pipeline(
  old_source : String,
  new_source : String,
) -> DiffPipelineContext {
  DiffPipelineContext::new(
    @diff_ignore.SourceView::from_source(old_source),
    @diff_ignore.SourceView::from_source(new_source),
    0,
    3_000_000,
    fallback_test_limit(),
    false,
  )
}

///|
test "root syntax-position overflow uses a whole-file lexical fallback" {
  let old_source = "old_root"
  let new_source = "new_root"
  let result = detailed_ast_root_list_document(
    [fallback_test_unit(old_source, 1, 99)],
    [fallback_test_unit(new_source, 1, 98)],
    fallback_test_pipeline(old_source, new_source),
  )
  guard result.document is Whole(fragment) else {
    fail("expected a whole document")
  }
  guard fragment.fallbacks is [SyntaxPositionsOutOfBounds(sides=[Old, New])] else {
    fail("expected a two-sided whole-file position fallback")
  }
  assert_false(fragment.document.hunks.is_empty())
}

///|
test "unit syntax-position overflow falls back locally and AST-diffs later units" {
  let old_source = "old_bad\nold_good"
  let new_source = "new_bad\nnew_good"
  let bad_old = fallback_test_unit("old_bad", 1, 99)
  let bad_new = fallback_test_unit("new_bad", 1, 1)
  let good_old = fallback_test_unit("old_good", 2, 2)
  let good_new = fallback_test_unit("new_good", 2, 2)
  let plan = per_unit_plan([
    Replace(old=bad_old, new=bad_new),
    Replace(old=good_old, new=good_new),
  ])
  let result = detailed_ast_plan_document(
    plan,
    fallback_test_pipeline(old_source, new_source),
  )
  guard result.document is TopLevel(top) else {
    fail("expected a sectioned document")
  }
  guard top.sections is [Matched(diff=bad, ..), Matched(diff=good, ..)] else {
    fail("expected two matched sections")
  }
  guard bad.fallbacks is [SyntaxPositionsOutOfBounds(sides=[Old])] else {
    fail("expected only the invalid declaration to fall back")
  }
  assert_true(good.fallbacks.is_empty())
  let bad_patch = @unified.render_unified_hunks(bad.document).join("")
  let good_patch = @unified.render_unified_hunks(good.document).join("")
  assert_true(bad_patch.contains("old_bad"), msg=bad_patch)
  assert_true(bad_patch.contains("new_bad"), msg=bad_patch)
  assert_true(good_patch.contains("old_good"), msg=good_patch)
  assert_true(good_patch.contains("new_good"), msg=good_patch)
  assert_true(top.old_order is [0, 1])
  assert_true(top.new_order is [0, 1])
}
