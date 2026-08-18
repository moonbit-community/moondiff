///|
/// Renderer-free diff options. Display labels, colors, and layouts belong to
/// consumers and are intentionally absent from this calculation API.
struct DiffOptions {
  context_lines : Int
  graph_limit : UInt
  ignore_comments : Bool
}

///|
/// Construct safe options, clamping a negative context radius to zero.
pub fn DiffOptions::new(
  context_lines? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
) -> DiffOptions {
  {
    context_lines: if context_lines < 0 {
      0
    } else {
      context_lines
    },
    graph_limit,
    ignore_comments,
  }
}

///|
pub impl Default for DiffOptions with fn default() {
  DiffOptions::new()
}

///|
pub type DiffDocument = @tokdiff.DiffDocument

///|
pub type DiffHunk = @tokdiff.DiffHunk

///|
pub type DiffBlock = @tokdiff.DiffBlock

///|
pub type DiffRow = @tokdiff.DiffRow

///|
pub type DiffLine = @tokdiff.DiffLine

///|
pub type DiffSegment = @tokdiff.DiffSegment

///|
pub type DiffSegmentKind = @tokdiff.DiffSegmentKind

///|
pub type ContextLine = @tokdiff.ContextLine

///|
pub type DiffStatus = @alignment.DiffStatus

///|
pub type DiffSide = @alignment.DiffSide

///|
pub type ComputationStage = @alignment.ComputationStage

///|
pub type FallbackReason = @alignment.FallbackReason

///|
pub type LineRange = @alignment.LineRange

///|
pub type FallbackScope = @alignment.FallbackScope

///|
pub type FallbackInfo = @alignment.FallbackInfo

///|
/// A calculated document plus classification and typed degradation metadata.
/// Its representation is private; use the accessor methods below.
struct DiffResult {
  document : DiffDocument
  status : DiffStatus
  fallbacks : Array[FallbackInfo]
}

///|
pub fn DiffResult::document(self : DiffResult) -> DiffDocument {
  self.document
}

///|
pub fn DiffResult::status(self : DiffResult) -> DiffStatus {
  self.status
}

///|
pub fn DiffResult::fallbacks(self : DiffResult) -> Array[FallbackInfo] {
  self.fallbacks.copy()
}

///|
pub fn DiffResult::has_fallback(self : DiffResult) -> Bool {
  !self.fallbacks.is_empty()
}
