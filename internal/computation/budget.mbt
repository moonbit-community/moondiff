///|
/// The structural-diff phase that requested work from a file-level computation
/// budget.
pub(all) enum Stage {
  TopLevelAlignment
  SyntaxMatching
  IntralineMatching
} derive(Debug, Eq)

///|
/// Raised before allocating a matrix whose work would exceed the shared
/// file-level budget.
pub(all) suberror LimitExceeded {
  LimitExceeded(stage~ : Stage, limit~ : UInt)
} derive(Debug, Eq)

///|
/// A shared monotonically-decreasing work budget. The limit is retained so
/// fallback metadata reports the configured ceiling rather than the amount
/// left at the point of failure.
pub struct Budget {
  limit : UInt
  remaining : Ref[UInt]
}

///|
pub fn Budget::new(limit : UInt) -> Budget {
  { limit, remaining: Ref(limit), }
}

///|
pub fn default_limit() -> UInt {
  2_000_000
}

///|
pub fn Budget::charge(
  self : Budget,
  units : UInt,
  stage : Stage,
) -> Unit raise LimitExceeded {
  if units > self.remaining.val {
    raise LimitExceeded(stage~, limit=self.limit)
  }
  self.remaining.val -= units
}

///|
/// Charge `rows * columns` units without first multiplying potentially large
/// dimensions. This check must precede every corresponding matrix allocation.
pub fn Budget::charge_matrix(
  self : Budget,
  rows : Int,
  columns : Int,
  stage : Stage,
) -> Unit raise LimitExceeded {
  if rows < 0 || columns < 0 {
    raise LimitExceeded(stage~, limit=self.limit)
  }
  let rows = rows.reinterpret_as_uint()
  let columns = columns.reinterpret_as_uint()
  if rows != 0 && columns > self.remaining.val / rows {
    raise LimitExceeded(stage~, limit=self.limit)
  }
  self.charge(rows * columns, stage)
}
