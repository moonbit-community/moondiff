///|
/// Internal result for AST graph traversal. Computation-budget exhaustion
/// remains a checked error, while reaching the configured graph size is an
/// expected fallback condition for callers to handle explicitly.
pub(all) enum GraphLimitResult[T] {
  WithinLimit(T)
  GraphLimitExceeded
}
