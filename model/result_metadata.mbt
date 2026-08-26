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
/// Side collections are exposed as zero-copy read-only views with stable
/// backing storage.
pub(all) enum FallbackReason {
  ParseError(sides~ : ArrayView[DiffSide], detail~ : String)
  /// A structural position did not belong to the rendered source lines for
  /// one or both sides, so indexing it would have been unsafe.
  SyntaxPositionsOutOfBounds(sides~ : ArrayView[DiffSide])
  GraphLimitExceeded(limit~ : UInt)
  ComputationLimitExceeded(stage~ : ComputationStage, limit~ : UInt)
  /// Lexical declaration alignment found no changes inside matched
  /// declarations, so the entire file was diffed to expose reordering.
  TopLevelReordering
} derive(Debug, Eq)

///|
/// A zero-based source range.
pub(all) struct LineRange {
  start : Int
  len : Int
} derive(Debug, Eq)

///|
/// One top-level source section retained by structural alignment. Either side
/// may be absent for an inserted or deleted declaration.
pub(all) struct DiffSection {
  old : LineRange?
  new : LineRange?
} derive(Debug, Eq)

///|
/// Renderer-neutral presentation grouping calculated alongside a document.
/// Section collections are exposed as read-only views whose backing storage is
/// never mutated after publication.
pub(all) enum DiffLayout {
  WholeDocument
  TopLevelSections(ArrayView[DiffSection])
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
