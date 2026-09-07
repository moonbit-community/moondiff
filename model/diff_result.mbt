///|
/// A complete semantic result. Its representation is opaque to consumers.
struct DiffResult {
  status : DiffStatus
  document : DiffDocument
  ignore_reason : IgnoreReason?
}

///|
/// Internal construction boundary for the calculation facade.
#internal(internal, "construct DiffResult only in moondiff calculation code")
pub fn DiffResult::make(
  document : DiffDocument,
  status : DiffStatus,
  ignore_reason? : IgnoreReason = FilteredContent,
) -> DiffResult {
  {
    status,
    document,
    ignore_reason: if status is IgnoredOnly {
      Some(ignore_reason)
    } else {
      None
    },
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
/// Return the filtering reason for `IgnoredOnly`, or `None` for every other
/// status, including `Identical`.
pub fn DiffResult::ignore_reason(self : DiffResult) -> IgnoreReason? {
  self.ignore_reason
}
