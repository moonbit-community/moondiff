///|
/// CLI diff calculation and display options.
pub struct Options {
  context_lines : Int
  graph_limit : UInt
  use_color : Bool
  ignore_comments : Bool
  ignore_tests : Bool
}

///|
/// Construct safe CLI options, clamping a negative context radius to zero.
pub fn Options::new(
  context_lines? : Int = 3,
  graph_limit? : UInt = 3_000_000,
  use_color? : Bool = false,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> Options {
  {
    context_lines: if context_lines < 0 {
      0
    } else {
      context_lines
    },
    graph_limit,
    use_color,
    ignore_comments,
    ignore_tests,
  }
}

///|
pub impl Default for Options with fn default() {
  Options::new()
}
