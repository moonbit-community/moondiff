///|
/// One independently calculated semantic fragment. Its hunk indexes are
/// local to the fragment; original-file coordinates live on its section.
pub(all) struct DiffFragment {
  document : HunkDocument
  fallbacks : ArrayView[FallbackReason]
} derive(Eq)

///|
/// One stable top-level pairing identity. Missing sides are represented by
/// distinct variants rather than fabricated empty ranges or cursors. Each
/// available context is the trimmed declaration-keyword source line.
pub(all) enum DiffSection {
  Matched(
    old~ : LineRange,
    new~ : LineRange,
    old_context~ : String?,
    new_context~ : String?,
    diff~ : DiffFragment
  )
  Deleted(old~ : LineRange, old_context~ : String?, diff~ : DiffFragment)
  Inserted(new~ : LineRange, new_context~ : String?, diff~ : DiffFragment)
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
