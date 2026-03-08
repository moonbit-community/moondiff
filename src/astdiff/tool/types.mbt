///|UUID(199e1683-8dce-4b5b-ade5-21d8199f249b)
pub struct DiffOptions {
  graph_limit : UInt
  context_lines : Int
  use_color : Bool
}

///|UUID(4b4b0094-f004-4736-8152-8313861cbdf7)
pub fn DiffOptions::new(
  graph_limit? : UInt = 3_000_000,
  context_lines? : Int = 3,
  use_color? : Bool = false,
) -> Self {
  { graph_limit, context_lines, use_color }
}

///|UUID(67af8150-11cf-4e6a-93e4-32813df70c26)
pub impl Default for DiffOptions with default() {
  DiffOptions::new()
}

///|UUID(3056bc33-5b65-4d21-bdfc-d602536de30d)
pub enum DiffKind {
  Ast
  TextFallback(reason~ : String)
}

///|UUID(9fb5ba8b-d057-4c8d-b7f8-2bed3405b0a4)
pub struct DiffResult {
  kind : DiffKind
  rendered : String
  has_changes : Bool
}

///|UUID(459e9d80-820e-405f-9121-29bb74069f9c)
pub fn DiffResult::is_fallback(self : Self) -> Bool {
  self.kind is TextFallback(_)
}
