///|
fn fallback_test_span(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> @span.SingleLineSpan {
  { line, start_col, end_col }
}

///|
fn fallback_test_novel(
  line : Int,
  start_col : Int,
  end_col : Int,
) -> MatchedPos {
  { kind: Novel, pos: fallback_test_span(line, start_col, end_col) }
}

///|
fn fallback_test_unchanged(
  pos : @span.SingleLineSpan,
  opposite : @span.SingleLineSpan,
) -> MatchedPos {
  { kind: Unchanged(opposite_pos=[opposite]), pos }
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
  guard mapped is [{ kind: Unchanged(opposite_pos=[]), pos }] else {
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
    start_line,
    source,
  }
}

///|
fn fallback_test_budget() -> @computation.Budget {
  @computation.Budget::new(@computation.default_limit())
}

///|
test "root syntax-position overflow uses a whole-file lexical fallback" {
  let old_source = "old_root"
  let new_source = "new_root"
  let result = detailed_ast_root_list_document(
    [fallback_test_unit(old_source, 1, 99)],
    [fallback_test_unit(new_source, 1, 98)],
    @diff_ignore.SourceView::from_source(old_source),
    @diff_ignore.SourceView::from_source(new_source),
    0,
    3_000_000,
    false,
    fallback_test_budget(),
  )
  guard result.fallbacks
    is [
      { reason: SyntaxPositionsOutOfBounds(sides=[Old, New]), scope: WholeFile },
    ] else {
    fail("expected a two-sided whole-file position fallback")
  }
  assert_false(result.document.hunks.is_empty())
}

///|
test "unit syntax-position overflow falls back locally and AST-diffs later units" {
  let old_source = "old_bad\nold_good"
  let new_source = "new_bad\nnew_good"
  let bad_old = fallback_test_unit("old_bad", 1, 99)
  let bad_new = fallback_test_unit("new_bad", 1, 1)
  let good_old = fallback_test_unit("old_good", 2, 2)
  let good_new = fallback_test_unit("new_good", 2, 2)
  let plan = PerUnit([
    { edit: Replace(old=bad_old, new=bad_new), old_offset: 0, new_offset: 0 },
    { edit: Replace(old=good_old, new=good_new), old_offset: 1, new_offset: 1 },
  ])
  let result = detailed_ast_plan_document(
    plan,
    @diff_ignore.SourceView::from_source(old_source),
    @diff_ignore.SourceView::from_source(new_source),
    0,
    3_000_000,
    false,
    fallback_test_budget(),
  )
  guard result.fallbacks
    is [
      {
        reason: SyntaxPositionsOutOfBounds(sides=[Old]),
        scope: Region(
          old=Some({ start: 0, len: 1 }),
          new=Some({ start: 0, len: 1 })
        ),
      },
    ] else {
    fail("expected only the invalid declaration to fall back")
  }
  let patch = @unified.render_unified_hunks(result.document).join("")
  assert_true(patch.contains("old_bad"), msg=patch)
  assert_true(patch.contains("new_bad"), msg=patch)
  assert_true(patch.contains("old_good"), msg=patch)
  assert_true(patch.contains("new_good"), msg=patch)
  assert_true(layout_from_top_level_plan(plan) is TopLevelSections([_, _]))
}

///|
test "one-sided syntax fallback honors its positioned missing-side cursor" {
  let old_source = "old_keep\nold_tail"
  let new_source = "new_keep\nnew_bad\nnew_tail"
  let inserted = fallback_test_unit("new_bad", 2, 99)
  let plan = PerUnit([{ edit: Insert(inserted), old_offset: 1, new_offset: 1 }])
  let result = detailed_ast_plan_document(
    plan,
    @diff_ignore.SourceView::from_source(old_source),
    @diff_ignore.SourceView::from_source(new_source),
    0,
    3_000_000,
    false,
    fallback_test_budget(),
  )
  guard result.fallbacks
    is [
      {
        reason: SyntaxPositionsOutOfBounds(sides=[New]),
        scope: Region(old=None, new=Some({ start: 1, len: 1 })),
      },
    ] else {
    fail("expected a new-only regional position fallback")
  }
  guard result.document.hunks is [hunk] else {
    fail("expected one lexical fallback hunk")
  }
  @debug.assert_eq(
    (hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len),
    (1, 0, 1, 1),
  )
  let patch = @unified.render_unified_hunks(result.document).join("")
  assert_true(patch.has_prefix("@@ -1,0 +2 @@\n"), msg=patch)
}
