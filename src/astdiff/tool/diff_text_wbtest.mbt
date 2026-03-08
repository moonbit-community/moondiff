///|UUID(8770cc34-040b-4ff6-8b09-aaedb8b7695c)
fn build_ast_change_map(
  old_source : String,
  new_source : String,
) -> (Array[@syntax.Syntax], Array[@syntax.Syntax], @diff.ChangeMap) {
  let (old_impls, old_reports) = @parser.parse_string(old_source)
  let (new_impls, new_reports) = @parser.parse_string(new_source)
  if old_reports.length() != 0 || new_reports.length() != 0 {
    panic()
  }

  let lhs_roots = @elab.elab_impls(old_source, old_impls)
  let rhs_roots = @elab.elab_impls(new_source, new_impls)
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @diff.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, 3_000_000) catch {
    _ => panic()
  }
  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)
  (lhs_roots, rhs_roots, change_map)
}

///|UUID(0c2c36b1-de77-483c-976e-ad2c6e594952)
fn total_width(ranges : Array[(Int, Int)]) -> Int {
  ranges.fold(init=0, fn(acc, range) {
    let (start_col, end_col) = range
    acc + (end_col - start_col)
  })
}

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
) -> MatchedPos {
  MatchedPos::{
    kind: Unchanged(opposite_pos=[whole_line_span(opposite_line, opposite_text)]),
    pos: whole_line_span(line, text),
  }
}

///|UUID(afd77686-8cd9-4975-809d-0c95062a6301)
fn merge_fixture() -> (String, String, Array[MatchedPos], Array[MatchedPos]) {
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
  let old_lines = split_lines(old_source)
  let new_lines = split_lines(new_source)

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
    MatchedPos::{
      kind: Novel,
      pos: @span.SingleLineSpan::{ line: 2, start_col: 7, end_col: 10 },
    },
    unchanged_line(3, new_lines[2], 3, old_lines[2]),
    unchanged_line(5, new_lines[4], 5, old_lines[4]),
    unchanged_line(7, new_lines[6], 7, old_lines[6]),
    unchanged_line(8, new_lines[7], 8, old_lines[7]),
    MatchedPos::{
      kind: Novel,
      pos: @span.SingleLineSpan::{ line: 8, start_col: 9, end_col: 14 },
    },
    unchanged_line(9, new_lines[8], 9, old_lines[8]),
  ]
  (old_source, new_source, lhs_positions, rhs_positions)
}

///|UUID(eee84f8a-6f63-41c8-b877-cdc6c2755043)
test "collect_novel_ranges keeps wrapped call argument unchanged on rhs" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let (_, rhs_roots, change_map) = build_ast_change_map(old_source, new_source)
  let rhs_ranges = collect_novel_ranges(change_positions(rhs_roots, change_map))
  let line_ranges = rhs_ranges.get(1).unwrap_or_else(() => panic())

  assert_true(line_ranges.length() > 0)
  assert_true(total_width(line_ranges) < "  foo(baz(bar))".length())
}

///|UUID(eb58afe1-9292-40e7-a9e5-16b8822390ef)
test "matched_pos_to_hunks keeps wrapped call on the same line pair" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let (lhs_roots, rhs_roots, change_map) = build_ast_change_map(
    old_source, new_source,
  )
  let hunks = matched_pos_to_hunks(
    change_positions(lhs_roots, change_map),
    change_positions(rhs_roots, change_map),
  )

  assert_eq(hunks.length(), 1)
  assert_eq(hunks[0].lines.length(), 1)
  assert_eq(hunks[0].lines[0], (Some(1), Some(1)))
  assert_true(!hunks[0].novel_lhs.contains(1))
  assert_true(hunks[0].novel_rhs.contains(1))
}

///|UUID(f7484963-12c3-48b8-a085-34e43d3eaf1b)
test "collect_novel_ranges narrows string replacement to changed word" {
  let old_source =
    #|fn f() {
    #|  println("alpha beta gamma")
    #|}
  let new_source =
    #|fn f() {
    #|  println("alpha zeta gamma")
    #|}
  let (_, rhs_roots, change_map) = build_ast_change_map(old_source, new_source)
  let rhs_ranges = collect_novel_ranges(change_positions(rhs_roots, change_map))
  let line_ranges = rhs_ranges.get(1).unwrap_or_else(() => panic())

  assert_true(line_ranges.length() > 0)
  assert_true(
    total_width(line_ranges) < "  println(\"alpha zeta gamma\")".length(),
  )
}

///|UUID(84aa462a-6685-44cd-a48f-033a85cbad5c)
test "merge_adjacent_hunks combines overlapping context windows" {
  let (old_source, new_source, lhs_positions, rhs_positions) = merge_fixture()
  let old_lines = split_lines(old_source)
  let new_lines = split_lines(new_source)
  let matched_lines = all_matched_lines_filled(
    lhs_positions, rhs_positions, old_lines, new_lines,
  )
  let hunks = matched_pos_to_hunks(lhs_positions, rhs_positions)

  assert_eq(hunks.length(), 2)

  let merged = merge_adjacent_hunks(hunks, matched_lines, 3)
  assert_eq(merged.length(), 1)

  let (start, end_) = contextual_index_range_for_hunk(
    merged[0],
    matched_lines,
    3,
  )
  assert_eq((start, end_), (0, matched_lines.length()))
}

///|UUID(cb822c15-f51a-4177-bfaf-a6b59daae2eb)
test "render_ast_diff uses one merged hunk for nearby ast changes" {
  let (old_source, new_source, lhs_positions, rhs_positions) = merge_fixture()
  let rendered = render_ast_diff(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    lhs_positions,
    rhs_positions,
    DiffOptions::new(context_lines=3),
  )

  assert_eq(rendered.split("@@").count(), 3)
  assert_true(rendered.contains("  5 | fn mid() {}"))
  assert_true(rendered.contains("+ 2 |   foo(baz(bar))"))
  assert_true(rendered.contains("+ 8 |   alpha(gamma(beta))"))
}
