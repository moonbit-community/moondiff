///|
fn paired_rows(
  document : @model.DiffDocument,
) -> Array[(@model.DiffLine, @model.DiffLine)] {
  let pairs = []
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ChangeBlock(rows) =>
          for row in rows {
            if row is Paired(old_line, new_line) {
              pairs.push((old_line, new_line))
            }
          }
        ContextBlock(_) | IgnoredBlock(_) => ()
      }
    }
  }
  pairs
}

///|
fn line_is_refined(line : @model.DiffLine) -> Bool {
  line.segments.any(segment => segment.kind is Changed)
}

///|
test "line diff shares refinement tokens across rows in one replacement" {
  let old = ["alpha old omega", "beta old omega"]
  let new = ["alpha new omega", "beta new omega"]
  let document = line_diff_with_budget(
    old,
    new,
    0,
    @worddiff.RefinementBudget::new(
      line_character_limit=100,
      character_limit=100,
      token_limit=10,
    ),
  )
  guard paired_rows(document)
    is [(first_old, first_new), (second_old, second_new)] else {
    fail("expected two rows in one positional replacement")
  }
  assert_true(line_is_refined(first_old) && line_is_refined(first_new))
  assert_false(line_is_refined(second_old) || line_is_refined(second_new))
}

///|
test "line diff shares refinement tokens across hunks without changing output" {
  let old = [
    "alpha old omega", "same one", "same two", "same three", "beta old omega",
  ]
  let new = [
    "alpha new omega", "same one", "same two", "same three", "beta new omega",
  ]
  let limited = line_diff_with_budget(
    old,
    new,
    0,
    @worddiff.RefinementBudget::new(
      line_character_limit=100,
      character_limit=100,
      token_limit=10,
    ),
  )
  let abundant = line_diff_with_budget(
    old,
    new,
    0,
    @worddiff.RefinementBudget::new(
      line_character_limit=100,
      character_limit=100,
      token_limit=20,
    ),
  )
  guard limited.hunks is [first_hunk, second_hunk] else {
    fail("expected two separated hunks")
  }
  assert_eq(
    (
      first_hunk.old_start,
      first_hunk.old_len,
      first_hunk.new_start,
      first_hunk.new_len,
    ),
    (0, 1, 0, 1),
  )
  assert_eq(
    (
      second_hunk.old_start,
      second_hunk.old_len,
      second_hunk.new_start,
      second_hunk.new_len,
    ),
    (4, 1, 4, 1),
  )
  guard paired_rows(limited)
    is [(first_old, first_new), (second_old, second_new)] else {
    fail("expected one positional pair in each hunk")
  }
  assert_true(line_is_refined(first_old) && line_is_refined(first_new))
  assert_false(line_is_refined(second_old) || line_is_refined(second_new))
  assert_eq((first_old.index, first_new.index), (0, 0))
  assert_eq((second_old.index, second_new.index), (4, 4))
  assert_eq((first_old.text(), first_new.text()), (old[0], new[0]))
  assert_eq((second_old.text(), second_new.text()), (old[4], new[4]))
  assert_eq(
    @unified.render_unified_hunks(limited),
    @unified.render_unified_hunks(abundant),
  )
}

///|
test "rejected character precharge leaves room for a later line" {
  let old = ["abcdefghijx", "same one", "same two", "a old"]
  let new = ["abcdefghijy", "same one", "same two", "a new"]
  let document = line_diff_with_budget(
    old,
    new,
    0,
    @worddiff.RefinementBudget::new(
      line_character_limit=100,
      character_limit=10,
      token_limit=6,
    ),
  )
  guard paired_rows(document)
    is [(large_old, large_new), (small_old, small_new)] else {
    fail("expected both positional replacement pairs")
  }
  assert_false(line_is_refined(large_old) || line_is_refined(large_new))
  assert_true(line_is_refined(small_old) && line_is_refined(small_new))
  assert_eq((large_old.text(), large_new.text()), (old[0], new[0]))
  assert_eq((small_old.text(), small_new.text()), (old[3], new[3]))
}
