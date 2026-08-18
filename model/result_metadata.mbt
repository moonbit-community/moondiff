///|
/// High-level classification of a renderer-free diff result.
pub(all) enum DiffStatus {
  Identical
  Changed
  NoStructuralChanges
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
pub(all) enum FallbackReason {
  ParseError(sides~ : Array[DiffSide], detail~ : String)
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
