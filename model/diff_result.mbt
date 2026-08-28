///|
/// A complete semantic result. Its representation is opaque to consumers.
struct DiffResult {
  status : DiffStatus
  document : DiffDocument
  old_ignored_test_ranges : Array[LineRange]
  new_ignored_test_ranges : Array[LineRange]
}

///|
/// Internal construction boundary for the calculation facade.
#internal(internal, "construct DiffResult only in moondiff calculation code")
pub fn DiffResult::make(
  document : DiffDocument,
  status : DiffStatus,
  old_ignored_test_ranges : ArrayView[LineRange],
  new_ignored_test_ranges : ArrayView[LineRange],
) -> DiffResult {
  {
    status,
    document,
    old_ignored_test_ranges: old_ignored_test_ranges.to_owned(),
    new_ignored_test_ranges: new_ignored_test_ranges.to_owned(),
  }
}

///|
/// Return the high-level classification of this result.
pub fn DiffResult::status(self : DiffResult) -> DiffStatus {
  self.status
}

///|
/// Return the sole semantic document retained by this result.
pub fn DiffResult::document(self : DiffResult) -> DiffDocument {
  self.document
}

///|
/// Return the zero-based physical line ranges of tests excluded from one input
/// by `ignore_tests`. Each test or async test has its own source-ordered range,
/// including directly owned `///` documentation and UUID/separator markers,
/// but excluding adjacent ordinary comments and blank separator lines.
///
/// The ranges describe each side independently and do not imply cross-side
/// test pairing. The returned view is read-only and has stable backing storage.
/// It is empty when test filtering is disabled, parsing fails, or identical
/// inputs take the comparison fast path.
pub fn DiffResult::ignored_test_ranges(
  self : DiffResult,
  side : DiffSide,
) -> ArrayView[LineRange] {
  match side {
    Old => self.old_ignored_test_ranges[:]
    New => self.new_ignored_test_ranges[:]
  }
}
