///|
test "matrix charges stop before multiplication or allocation" {
  let budget = @computation.ScopeBudget::new(6)
  budget.charge_matrix(2, 3, TopLevelAlignment)
  try budget.charge_matrix(1, 1, SyntaxMatching) catch {
    @computation.ScopeLimitExceeded(stage~, limit~) => {
      assert_true(stage is SyntaxMatching)
      assert_eq(limit, 6U)
    }
  } noraise {
    _ => fail("expected the budget to be exhausted")
  }

  let tiny = @computation.ScopeBudget::new(1)
  try
    tiny.charge_matrix(2_000_000_000, 2_000_000_000, IntralineMatching)
  catch {
    @computation.ScopeLimitExceeded(stage~, limit~) => {
      assert_true(stage is IntralineMatching)
      assert_eq(limit, 1U)
    }
  } noraise {
    _ => fail("expected overflow-safe rejection")
  }
}
