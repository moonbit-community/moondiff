///|
/// The structural-diff stage that requested work from the current independently
/// budgeted calculation scope.
pub(all) enum Stage {
  TopLevelAlignment
  SyntaxMatching
  IntralineMatching
} derive(Debug, Eq)

///|
/// Raised before work would exceed the current calculation scope's budget.
/// Independent scopes do not charge one aggregate file-level budget.
pub(all) suberror ScopeLimitExceeded {
  ScopeLimitExceeded(stage~ : Stage, limit~ : UInt)
} derive(Debug, Eq)

///|
/// A monotonically-decreasing budget shared within one calculation scope.
/// Callers create fresh budgets for independent scopes. The limit is retained
/// so fallback metadata reports the scope ceiling rather than remaining work.
pub struct ScopeBudget {
  limit : UInt
  remaining : Ref[UInt]
}

///|
pub fn ScopeBudget::new(limit : UInt) -> ScopeBudget {
  { limit, remaining: Ref(limit), }
}

///|
/// Return the default work ceiling for each independent calculation scope.
pub fn default_scope_limit() -> UInt {
  2_000_000
}

///|
pub fn ScopeBudget::charge(
  self : ScopeBudget,
  units : UInt,
  stage : Stage,
) -> Unit raise ScopeLimitExceeded {
  if units > self.remaining.val {
    raise ScopeLimitExceeded(stage~, limit=self.limit)
  }
  self.remaining.val -= units
}

///|
/// Charge `rows * columns` units without first multiplying potentially large
/// dimensions. This check must precede every corresponding matrix allocation.
pub fn ScopeBudget::charge_matrix(
  self : ScopeBudget,
  rows : Int,
  columns : Int,
  stage : Stage,
) -> Unit raise ScopeLimitExceeded {
  if rows < 0 || columns < 0 {
    raise ScopeLimitExceeded(stage~, limit=self.limit)
  }
  let rows = rows.reinterpret_as_uint()
  let columns = columns.reinterpret_as_uint()
  if rows != 0 && columns > self.remaining.val / rows {
    raise ScopeLimitExceeded(stage~, limit=self.limit)
  }
  self.charge(rows * columns, stage)
}
