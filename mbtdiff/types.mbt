///|
/// Select whether MoonBit changes are compared structurally or lexically.
///
/// `Lexical` compares token-level text inside the selected semantic fragments.
/// Once reliable top-level alignment produces independent declaration
/// sections, whitespace-only lines outside every section (at file boundaries
/// or between declarations) are intentionally outside the comparison. A
/// whole-file lexical result still compares those lines.
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
/// A renderer-ready hunk diff for one semantic fragment.
pub type HunkDocument = @model.HunkDocument

///|
/// The high-level semantic document returned by `DiffResult::document`.
/// Consumers must match `Whole` or `TopLevel` before rendering fragments.
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
pub type DiffFragment = @model.DiffFragment

///|
pub type DiffSection = @model.DiffSection

///|
pub type TopLevelDiff = @model.TopLevelDiff

///|
/// An opaque calculation result exposing only `status` and `document`.
pub type DiffResult = @model.DiffResult
