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
pub type DiffDocument = @model.DiffDocument

///|
pub type DiffHunk = @model.DiffHunk

///|
pub type DiffBlock = @model.DiffBlock

///|
pub type DiffRow = @model.DiffRow

///|
pub type DiffLine = @model.DiffLine

///|
pub type DiffSegment = @model.DiffSegment

///|
pub type DiffSegmentKind = @model.DiffSegmentKind

///|
pub type ContextLine = @model.ContextLine

///|
pub type DiffStatus = @model.DiffStatus

///|
pub type DiffSide = @model.DiffSide

///|
pub type ComputationStage = @model.ComputationStage

///|
pub type FallbackReason = @model.FallbackReason

///|
pub type LineRange = @model.LineRange

///|
pub type FallbackScope = @model.FallbackScope

///|
pub type FallbackInfo = @model.FallbackInfo

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
