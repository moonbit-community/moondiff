///|
/// The MoonBit-aware calculation engine used to build an aligned diff
/// document. Lexical mode retains token-level text changes inside the selected
/// whole-file or declaration-local fragments; AST mode reports only structural
/// changes.
pub(all) enum AlignedDiffMode {
  Lexical
  Ast
} derive(Eq)

///|
/// Detailed renderer-neutral alignment output. Public callers consume this
/// through the `mbtdiff` facade.
pub(all) struct DetailedDiffResult {
  document : @model.DiffDocument
  status : @model.DiffStatus
} derive(Eq)

///|
/// Calculate the sole renderer-neutral semantic document from one parse and
/// one top-level alignment plan. Reliable declaration pairings remain
/// section-local even when their two source orders cross. Section-local
/// lexical comparison returns each changed exact unit range in full, while
/// whitespace-only gaps outside those ranges are not represented as sections.
/// Caller context still controls Whole, AST, and AST-fallback documents.
pub fn calculate_diff_document(
  old_source : String,
  new_source : String,
  old_name? : String = "old",
  new_name? : String = "new",
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  calculate_diff_document_with_scope_limit(
    old_source,
    new_source,
    old_name,
    new_name,
    context,
    graph_limit,
    ignore_comments,
    @computation.default_scope_limit(),
    ignore_tests~,
    mode~,
  )
}

///|
/// Calculate a renderer-neutral diff and typed fallback metadata. AST mode is
/// the default. The independently applied per-scope computation limit is
/// deliberately fixed as an implementation detail.
pub fn diff_document_detailed(
  old_source : String,
  new_source : String,
  context? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
  mode? : AlignedDiffMode = Ast,
) -> DetailedDiffResult {
  calculate_diff_document(
    old_source,
    new_source,
    context~,
    graph_limit~,
    ignore_comments~,
    ignore_tests~,
    mode~,
  )
}
