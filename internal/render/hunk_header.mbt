///|
fn range_text(start : Int32, len : Int32) -> String {
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
  old_start : Int32,
  old_len : Int32,
  new_start : Int32,
  new_len : Int32,
) -> String {
  "@@ -\{range_text(old_start, old_len)} +\{range_text(new_start, new_len)} @@"
}
