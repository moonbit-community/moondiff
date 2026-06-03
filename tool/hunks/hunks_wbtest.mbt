///|UUID(d7228f90-8748-409c-85dc-e7e69ec96c77)
fn whole_line_span(line : Int, text : String) -> @span.SingleLineSpan {
  @span.SingleLineSpan::{ line, start_col: 1, end_col: text.length() + 1 }
}

///|UUID(18960ac7-e004-469c-be30-f51141e1a28f)
fn unchanged_line(
  line : Int,
  text : String,
  opposite_line : Int,
  opposite_text : String,
) -> @syntax.MatchedPos {
  @syntax.MatchedPos::{
    kind: @syntax.MatchKind::Unchanged(opposite_pos=[
      whole_line_span(opposite_line, opposite_text),
    ]),
    pos: whole_line_span(line, text),
  }
}

///|UUID(44fd5ac8-40bb-4819-93a8-73cb1f179e1f)
fn novel_span(line : Int, start_col : Int, end_col : Int) -> @syntax.MatchedPos {
  @syntax.MatchedPos::{
    kind: @syntax.MatchKind::Novel,
    pos: @span.SingleLineSpan::{ line, start_col, end_col },
  }
}

///|UUID(afd77686-8cd9-4975-809d-0c95062a6301)
fn merge_fixture() -> (
  String,
  String,
  Array[@syntax.MatchedPos],
  Array[@syntax.MatchedPos],
) {
  let old_source =
    #|fn a() {
    #|  foo(bar)
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(beta)
    #|}
  let new_source =
    #|fn a() {
    #|  foo(baz(bar))
    #|}
    #|
    #|fn mid() {}
    #|
    #|fn z() {
    #|  alpha(gamma(beta))
    #|}
  let old_lines = old_source.split("\n").map(line => line.to_owned()).collect()
  let new_lines = new_source.split("\n").map(line => line.to_owned()).collect()

  let lhs_positions = [
    unchanged_line(1, old_lines[0], 1, new_lines[0]),
    unchanged_line(2, old_lines[1], 2, new_lines[1]),
    unchanged_line(3, old_lines[2], 3, new_lines[2]),
    unchanged_line(5, old_lines[4], 5, new_lines[4]),
    unchanged_line(7, old_lines[6], 7, new_lines[6]),
    unchanged_line(8, old_lines[7], 8, new_lines[7]),
    unchanged_line(9, old_lines[8], 9, new_lines[8]),
  ]
  let rhs_positions = [
    unchanged_line(1, new_lines[0], 1, old_lines[0]),
    unchanged_line(2, new_lines[1], 2, old_lines[1]),
    novel_span(2, 7, 10),
    unchanged_line(3, new_lines[2], 3, old_lines[2]),
    unchanged_line(5, new_lines[4], 5, old_lines[4]),
    unchanged_line(7, new_lines[6], 7, old_lines[6]),
    unchanged_line(8, new_lines[7], 8, old_lines[7]),
    novel_span(8, 9, 14),
    unchanged_line(9, new_lines[8], 9, old_lines[8]),
  ]
  (old_source, new_source, lhs_positions, rhs_positions)
}

///|UUID(eb58afe1-9292-40e7-a9e5-16b8822390ef)
test "matched_pos_to_hunks keeps wrapped call on the same line pair" {
  let lhs_positions = [
    unchanged_line(1, "fn f() {", 1, "fn f() {"),
    unchanged_line(2, "  foo(bar)", 2, "  foo(baz(bar))"),
    unchanged_line(3, "}", 3, "}"),
  ]
  let rhs_positions = [
    unchanged_line(1, "fn f() {", 1, "fn f() {"),
    unchanged_line(2, "  foo(baz(bar))", 2, "  foo(bar)"),
    novel_span(2, 7, 10),
    unchanged_line(3, "}", 3, "}"),
  ]
  let hunks = matched_pos_to_hunks(lhs_positions, rhs_positions)

  @debug.assert_eq(hunks.length(), 1)
  @debug.assert_eq(hunks[0].lines.length(), 1)
  @debug.assert_eq(hunks[0].lines[0], (Some(1), Some(1)))
  assert_true(!hunks[0].novel_lhs.contains(1))
  assert_true(hunks[0].novel_rhs.contains(1))
}

///|UUID(84aa462a-6685-44cd-a48f-033a85cbad5c)
test "merge_adjacent_hunks combines overlapping context windows" {
  let (old_source, new_source, lhs_positions, rhs_positions) = merge_fixture()
  let old_lines = old_source.split("\n").map(line => line.to_owned()).collect()
  let new_lines = new_source.split("\n").map(line => line.to_owned()).collect()
  let matched_lines = all_matched_lines_filled(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  let hunks = matched_pos_to_hunks(lhs_positions, rhs_positions)

  @debug.assert_eq(hunks.length(), 2)

  let merged = merge_adjacent_hunks(hunks, matched_lines, 3)
  @debug.assert_eq(merged.length(), 1)

  let (start, end_) = contextual_index_range_for_hunk(
    merged[0],
    matched_lines,
    3,
  )
  @debug.assert_eq((start, end_), (0, matched_lines.length()))
}
