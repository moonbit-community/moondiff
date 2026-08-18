///|
fn range_text(start : Int, len : Int) -> String {
  if len == 1 {
    (start + 1).to_string()
  } else if len == 0 {
    "\{start},0"
  } else {
    "\{start + 1},\{len}"
  }
}

///|
/// Format the canonical unified-diff header for zero-based source ranges.
pub fn hunk_header(
  old_start : Int,
  old_len : Int,
  new_start : Int,
  new_len : Int,
) -> String {
  "@@ -\{range_text(old_start, old_len)} +\{range_text(new_start, new_len)} @@"
}
