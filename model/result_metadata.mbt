///|
/// High-level classification of a renderer-free diff result.
pub(all) enum DiffStatus {
  Identical
  Changed
  /// Matched top-level declarations occur in a different order, with no
  /// fragment-local text or structural changes.
  Reordered
  /// The inputs differ, but the selected comparison found no in-scope fragment
  /// change. This includes AST-only text changes and, for sectioned Lexical
  /// results, whitespace-only changes outside declaration-owned ranges.
  NoStructuralChanges
  /// The inputs differ only in content excluded by enabled filters.
  IgnoredOnly
} derive(Debug, Eq)

///|
/// The input side associated with a calculation fallback.
pub(all) enum DiffSide {
  Old
  New
} derive(Debug, Eq)

///|
/// A bounded stage of the structural diff calculation.
pub(all) enum ComputationStage {
  TopLevelAlignment
  SyntaxMatching
  IntralineMatching
} derive(Debug, Eq)

///|
/// The typed reason that structural diffing degraded to a lexical result.
/// Side collections are exposed as zero-copy read-only views with stable
/// backing storage.
pub(all) enum FallbackReason {
  ParseError(sides~ : ArrayView[DiffSide], detail~ : String)
  /// A structural position did not belong to the rendered source lines for
  /// one or both sides, so indexing it would have been unsafe.
  SyntaxPositionsOutOfBounds(sides~ : ArrayView[DiffSide])
  GraphLimitExceeded(limit~ : UInt)
  ComputationLimitExceeded(stage~ : ComputationStage, limit~ : UInt)
} derive(Debug, Eq)

///|
/// A zero-based source range.
pub(all) struct LineRange {
  start : Int
  len : Int
} derive(Debug, Eq)
