///|
pub fn diff_with_opt(
  old~ : ArrayView[MbtToken],
  new~ : ArrayView[MbtToken],
) -> Array[Edit[Array[Char]]] {
  let (prefix, suffix, old, new) = @preopt.separate_common_prefix_and_suffix(
    old~,
    new~,
  )
  let middle = @myers.diff(old~, new~)
  let edits = Array::new(
    capacity=prefix.length() + middle.length() + suffix.length(),
  )
  edits.push_iter(prefix.iter())
  edits.push_iter(middle.iter())
  edits.push_iter(suffix.iter())
  @compress.compress_edits(edits) |> @postopt.align_edit_boundaries
}
