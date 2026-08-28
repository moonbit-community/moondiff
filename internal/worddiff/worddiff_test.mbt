///|
fn reconstructed_line(segments : Array[@model.DiffSegment]) -> @model.DiffLine {
  { index: 0, segments: segments[:], }
}

///|
fn assert_segments(
  actual : Array[@model.DiffSegment],
  expected : Array[@model.DiffSegment],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for index in 0..<actual.length() {
    assert_true(actual[index] == expected[index])
  }
}

///|
test "word refinement highlights only changed runs and reconstructs exactly" {
  let old = "alpha beta gamma"
  let new = "alpha zeta gamma"
  guard @worddiff.refine_line(old, new) is Some((old_segments, new_segments)) else {
    fail("expected bounded word refinement")
  }
  assert_segments(old_segments, [
    { kind: Unchanged, text: "alpha ", },
    { kind: Changed, text: "beta", },
    { kind: Unchanged, text: " gamma", },
  ])
  assert_segments(new_segments, [
    { kind: Unchanged, text: "alpha ", },
    { kind: Changed, text: "zeta", },
    { kind: Unchanged, text: " gamma", },
  ])
  assert_eq(reconstructed_line(old_segments).text(), old)
  assert_eq(reconstructed_line(new_segments).text(), new)
}

///|
test "word refinement handles one-sided words whitespace punctuation and empties" {
  guard @worddiff.refine_line("alpha", "alpha beta")
    is Some((old_added, new_added)) else {
    fail("expected one-sided refinement")
  }
  assert_segments(old_added, [{ kind: Unchanged, text: "alpha", }])
  assert_segments(new_added, [
    { kind: Unchanged, text: "alpha", },
    { kind: Changed, text: " beta", },
  ])

  let old_space = "a \t\u{a0}b"
  let new_space = "a \t\u{3000}b"
  guard @worddiff.refine_line(old_space, new_space)
    is Some((old_whitespace, new_whitespace)) else {
    fail("expected Unicode whitespace refinement")
  }
  assert_segments(old_whitespace, [
    { kind: Unchanged, text: "a", },
    { kind: Changed, text: " \t\u{a0}", },
    { kind: Unchanged, text: "b", },
  ])
  assert_segments(new_whitespace, [
    { kind: Unchanged, text: "a", },
    { kind: Changed, text: " \t\u{3000}", },
    { kind: Unchanged, text: "b", },
  ])
  assert_eq(reconstructed_line(old_whitespace).text(), old_space)
  assert_eq(reconstructed_line(new_whitespace).text(), new_space)

  guard @worddiff.refine_line("foo(bar)", "foo(baz)")
    is Some((old_punctuation, new_punctuation)) else {
    fail("expected punctuation refinement")
  }
  assert_segments(old_punctuation, [{ kind: Changed, text: "foo(bar)", }])
  assert_segments(new_punctuation, [{ kind: Changed, text: "foo(baz)", }])

  guard @worddiff.refine_line("", "") is Some((old_empty, new_empty)) else {
    fail("expected empty refinement")
  }
  assert_true(old_empty.is_empty() && new_empty.is_empty())
  guard @worddiff.refine_line("", "word") is Some((old_empty, new_word)) else {
    fail("expected insertion into an empty line")
  }
  assert_true(old_empty.is_empty())
  assert_segments(new_word, [{ kind: Changed, text: "word", }])
}

///|
test "word refinement enforces each side's token limit independently" {
  let at_limit = "x ".repeat(2_048)
  let over_limit = at_limit + "x"
  assert_true(@worddiff.refine_line(at_limit, at_limit) is Some(_))
  assert_true(@worddiff.refine_line(over_limit, "x") is None)
  assert_true(@worddiff.refine_line("x", over_limit) is None)
}

///|
test "word refinement enforces UTF-16 line length boundaries" {
  let at_limit = "x".repeat(16_384)
  assert_true(@worddiff.refine_line(at_limit, at_limit) is Some(_))
  assert_true(@worddiff.refine_line(at_limit + "x", "x") is None)
  assert_true(@worddiff.refine_line("x", at_limit + "x") is None)

  let emoji_exact = @worddiff.RefinementBudget::new(
    line_character_limit=2,
    character_limit=4,
    token_limit=2,
  )
  assert_true(
    @worddiff.refine_line("😀", "😀", budget=emoji_exact) is Some(_),
  )
  let emoji_over = @worddiff.RefinementBudget::new(
    line_character_limit=1,
    character_limit=4,
    token_limit=2,
  )
  assert_true(@worddiff.refine_line("😀", "", budget=emoji_over) is None)
}

///|
test "shared character and token budgets accept exact totals" {
  let characters = @worddiff.RefinementBudget::new(
    line_character_limit=10,
    character_limit=6,
    token_limit=4,
  )
  assert_true(@worddiff.refine_line("abc", "def", budget=characters) is Some(_))
  assert_true(@worddiff.refine_line("a", "b", budget=characters) is None)

  let tokens = @worddiff.RefinementBudget::new(
    line_character_limit=10,
    character_limit=100,
    token_limit=6,
  )
  assert_true(@worddiff.refine_line("a b", "c d", budget=tokens) is Some(_))
  assert_true(@worddiff.refine_line("a", "b", budget=tokens) is None)
}

///|
test "failed pair charges are atomic so later small refinements can run" {
  let characters = @worddiff.RefinementBudget::new(
    line_character_limit=10,
    character_limit=5,
    token_limit=2,
  )
  assert_true(@worddiff.refine_line("abc", "def", budget=characters) is None)
  assert_true(@worddiff.refine_line("a", "b", budget=characters) is Some(_))

  let tokens = @worddiff.RefinementBudget::new(
    line_character_limit=10,
    character_limit=100,
    token_limit=5,
  )
  assert_true(@worddiff.refine_line("a b", "c d", budget=tokens) is None)
  assert_true(@worddiff.refine_line("a", "b", budget=tokens) is Some(_))
}

///|
test "replacement ranges accept both adjacent edit orders" {
  let edits = @diff.Diff(old=["old"], new=["new"]).edits()
  guard edits is [delete, insert] else {
    fail("expected one delete/insert replacement")
  }
  assert_eq(
    @worddiff.replacement_ranges(delete, insert),
    Some(((0, 1), (0, 1))),
  )
  assert_eq(
    @worddiff.replacement_ranges(insert, delete),
    Some(((0, 1), (0, 1))),
  )
  assert_true(@worddiff.replacement_ranges(delete, delete) is None)
}
