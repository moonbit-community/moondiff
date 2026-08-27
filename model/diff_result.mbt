///|
/// A complete semantic result. Its representation is opaque to consumers.
struct DiffResult {
  status : DiffStatus
  document : DiffDocument
}

///|
/// Internal construction boundary for the calculation facade.
#internal(internal, "construct DiffResult only in moondiff calculation code")
pub fn DiffResult::make(
  document : DiffDocument,
  status : DiffStatus,
) -> DiffResult {
  { status, document }
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
