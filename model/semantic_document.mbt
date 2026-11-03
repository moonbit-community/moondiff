///|
/// One independently calculated semantic fragment. Its hunk indexes are
/// local to the fragment; original-file coordinates live on its section.
#derive(Eq)
pub(all) struct DiffFragment {
  document : HunkDocument
  fallbacks : ArrayView[FallbackReason]
}

///|
/// One stable top-level pairing identity. Missing sides are represented by
/// distinct variants rather than fabricated empty ranges or cursors. Each
/// available context is the trimmed declaration-keyword source line.
#derive(Eq)
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
}

///|
/// A semantic top-level result. `sections` is an identity table; `old_order`
/// and `new_order` contain each section exactly once for every side it has,
/// sorted by that side's range. `reordered` compares only matched identities.
#derive(Eq)
pub(all) struct TopLevelDiff {
  sections : ArrayView[DiffSection]
  old_order : ArrayView[Int32]
  new_order : ArrayView[Int32]
  reordered : Bool
}

///|
/// The sole semantic diff document. `Whole` means the calculation could only
/// treat the input as one reliable fragment. `TopLevel` preserves independent
/// declaration pairings and both source orders.
#derive(Eq)
pub(all) enum DiffDocument {
  Whole(DiffFragment)
  TopLevel(TopLevelDiff)
}
