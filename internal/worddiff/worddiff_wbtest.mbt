///|
test "tokenization groups Unicode whitespace and keeps punctuation attached" {
  guard tokenize_line("foo(bar) \t\u{a0}\u{3000}baz") is Some(tokens) else {
    fail("expected tokenization within the limit")
  }
  assert_eq(tokens, ["foo(bar)", " \t\u{a0}\u{3000}", "baz"])
  assert_eq(tokens.join(""), "foo(bar) \t\u{a0}\u{3000}baz")
  assert_eq(tokenize_line(""), Some([]))
}

///|
test "tokenization accepts 4096 runs and rejects 4097" {
  let at_limit = "x ".repeat(2_048)
  let over_limit = at_limit + "x"
  guard tokenize_line(at_limit) is Some(tokens) else {
    fail("expected the exact token limit to be accepted")
  }
  assert_eq(tokens.length(), 4_096)
  assert_eq(tokenize_line(over_limit), None)
}

///|
test "budget accounting follows refinement rejection order" {
  let character_rejected = RefinementBudget::new(
    line_character_limit=10,
    character_limit=5,
    token_limit=7,
  )
  assert_true(refine_line("abc", "def", budget=character_rejected) is None)
  assert_eq(character_rejected.remaining_characters.val, 5U)
  assert_eq(character_rejected.remaining_tokens.val, 7U)

  let line_rejected = RefinementBudget::new(
    line_character_limit=3,
    character_limit=10,
    token_limit=7,
  )
  assert_true(refine_line("abcd", "x", budget=line_rejected) is None)
  assert_eq(line_rejected.remaining_characters.val, 5U)
  assert_eq(line_rejected.remaining_tokens.val, 7U)

  let token_count_rejected = RefinementBudget::new(
    line_character_limit=10,
    character_limit=20,
    token_limit=5,
  )
  assert_true(refine_line("a b", "c d", budget=token_count_rejected) is None)
  assert_eq(token_count_rejected.remaining_characters.val, 14U)
  assert_eq(token_count_rejected.remaining_tokens.val, 5U)
  assert_true(refine_line("a", "b", budget=token_count_rejected) is Some(_))
  assert_eq(token_count_rejected.remaining_characters.val, 12U)
  assert_eq(token_count_rejected.remaining_tokens.val, 3U)
}

///|
test "per-side token rejection leaves the shared token budget untouched" {
  let over_limit = "x ".repeat(2_048) + "x"
  let budget = RefinementBudget::new(character_limit=5_000, token_limit=2)
  assert_true(refine_line(over_limit, "x", budget~) is None)
  assert_eq(budget.remaining_characters.val, 902U)
  assert_eq(budget.remaining_tokens.val, 2U)
  assert_true(refine_line("a", "b", budget~) is Some(_))
}
