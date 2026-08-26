///|
/// Select whether MoonBit changes are compared structurally or lexically.
pub(all) enum DiffMode {
  Ast
  Lexical
} derive(Debug, Eq)

///|
/// Renderer-free diff options. Display labels, colors, and layouts belong to
/// consumers and are intentionally absent from this calculation API.
struct DiffOptions {
  context_lines : Int
  graph_limit : UInt
  ignore_comments : Bool
  ignore_tests : Bool
  mode : DiffMode
}

///|
/// Construct safe options, clamping a negative context radius to zero.
pub fn DiffOptions::DiffOptions(
  context_lines? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : DiffMode = Ast,
) -> DiffOptions {
  {
    context_lines: if context_lines < 0 {
      0
    } else {
      context_lines
    },
    graph_limit,
    ignore_comments,
    ignore_tests,
    mode,
  }
}

///|
pub impl Default for DiffOptions with fn default() {
  DiffOptions()
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
pub type DiffSection = @model.DiffSection

///|
pub type DiffLayout = @model.DiffLayout

///|
/// A calculated document plus classification, layout, and typed degradation
/// metadata. Its representation is private; use the accessor methods below.
/// Document collections, section layouts, and fallback metadata are returned
/// as zero-copy read-only views whose backing storage is never mutated after
/// this result is published.
struct DiffResult {
  document : DiffDocument
  status : DiffStatus
  fallbacks : ArrayView[FallbackInfo]
  layout : DiffLayout
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
pub fn DiffResult::fallbacks(self : DiffResult) -> ArrayView[FallbackInfo] {
  self.fallbacks
}

///|
pub fn DiffResult::layout(self : DiffResult) -> DiffLayout {
  self.layout
}
