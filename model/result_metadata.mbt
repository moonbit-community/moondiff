///|
/// High-level classification of a renderer-free diff result.
pub(all) enum DiffStatus {
  Identical
  Changed
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
/// Parse-error sides are exposed as a zero-copy read-only view with stable
/// backing storage.
pub(all) enum FallbackReason {
  ParseError(sides~ : ArrayView[DiffSide], detail~ : String)
  GraphLimitExceeded(limit~ : UInt)
  ComputationLimitExceeded(stage~ : ComputationStage, limit~ : UInt)
} derive(Debug, Eq)

///|
/// A zero-based source range.
pub(all) struct LineRange {
  start : Int
  len : Int
} derive(Debug, Eq)

///|
/// The source region affected by a calculation fallback.
pub(all) enum FallbackScope {
  WholeFile
  Region(old~ : LineRange?, new~ : LineRange?)
} derive(Debug, Eq)

///|
/// Typed degradation metadata for one fallback.
pub(all) struct FallbackInfo {
  reason : FallbackReason
  scope : FallbackScope
} derive(Debug, Eq)
