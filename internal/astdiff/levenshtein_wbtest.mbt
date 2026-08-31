///|UUID(970267b5-03be-4cdb-81df-7933d1d1755b)
#callsite(autofill(loc))
fn assert_delta(lhs : Double, rhs : Double, loc~ : SourceLoc) -> Unit raise {
  let delta = 0.00001
  if (lhs - rhs).abs() > delta {
    fail("\{loc}: (\{lhs} - \{rhs}).abs() > \{delta}")
  }
}

///|UUID(7e59d399-02da-4033-9686-5eca1a0043de)
test {
  let budget = @computation.ScopeBudget::new(@computation.default_scope_limit())
  assert_delta(
    normalized_levenshtein(lhs="kitten", rhs="sitting", budget),
    0.57142,
  )
  assert_delta(normalized_levenshtein(lhs="", rhs="", budget), 1.0)
  assert_delta(normalized_levenshtein(lhs="", rhs="second", budget), 0)
  assert_delta(normalized_levenshtein(lhs="first", rhs="", budget), 0)
  assert_delta(normalized_levenshtein(lhs="string", rhs="string", budget), 1.0)
}
