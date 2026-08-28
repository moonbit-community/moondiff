///|
/// Terminal-only display controls. Line-count hints reserve stable number
/// column widths when the calculated document contains only part of a file or
/// top-level section.
pub struct RenderOptions {
  use_color : Bool
  old_max_line : Int?
  new_max_line : Int?
}

///|
pub fn RenderOptions::new(
  use_color? : Bool = false,
  old_max_line? : Int,
  new_max_line? : Int,
) -> RenderOptions {
  { use_color, old_max_line, new_max_line, }
}

///|
pub impl Default for RenderOptions with fn default() {
  RenderOptions::new()
}
