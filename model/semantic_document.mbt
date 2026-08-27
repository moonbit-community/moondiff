///|
/// One independently calculated semantic fragment. A non-empty `rows` view is
/// complete, monotonically covers the selected fragment on both sides, and
/// uses fragment-local indexes. Empty rows mean the selected mode recognizes
/// no change. Original-file coordinates live on the enclosing section.
pub(all) struct DiffFragment {
  rows : ArrayView[DiffRow]
  fallbacks : ArrayView[FallbackReason]
} derive(Eq)

///|
/// One stable top-level pairing identity. Missing sides are represented by
/// distinct variants rather than fabricated empty ranges or cursors.
pub(all) enum DiffSection {
  Matched(old~ : LineRange, new~ : LineRange, diff~ : DiffFragment)
  Deleted(old~ : LineRange, diff~ : DiffFragment)
  Inserted(new~ : LineRange, diff~ : DiffFragment)
} derive(Eq)

///|
/// A semantic top-level result. `sections` is an identity table; `old_order`
/// and `new_order` contain each section exactly once for every side it has,
/// sorted by that side's range. `reordered` compares only matched identities.
pub(all) struct TopLevelDiff {
  sections : ArrayView[DiffSection]
  old_order : ArrayView[Int]
  new_order : ArrayView[Int]
  reordered : Bool
} derive(Eq)

///|
/// The sole semantic diff document. `Whole` means the calculation could only
/// treat the input as one reliable fragment. `TopLevel` preserves independent
/// declaration pairings and both source orders.
pub(all) enum DiffDocument {
  Whole(DiffFragment)
  TopLevel(TopLevelDiff)
} derive(Eq)
