///|UUID(e5dfaa90-0a16-4853-a9a8-21af65622a2a)
pub fn diff_with_opt(
  old~ : ArrayView[MbtToken],
  new~ : ArrayView[MbtToken],
) -> Array[Edit[Array[MbtToken]]] {
  let (prefix, suffix, old, new) = @preopt.separate_common_prefix_and_suffix(
    old~,
    new~,
  )
  let (_, middle) = @myers.diff(old~, new~)
  let edits = Array::new(
    capacity=prefix.length() + middle.length() + suffix.length(),
  )
  edits.push_iter(prefix.iter())
  edits.push_iter(middle.iter())
  edits.push_iter(suffix.iter())
  @compress.compress_edits(edits) |> @postopt.align_edit_boundaries
}
