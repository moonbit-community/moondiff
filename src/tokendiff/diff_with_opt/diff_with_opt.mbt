///|UUID(e5dfaa90-0a16-4853-a9a8-21af65622a2a)
pub fn diff_with_opt(
  old~ : ArrayView[MbtToken],
  new~ : ArrayView[MbtToken],
) -> Array[Edit[Array[MbtToken]]] {
  let (prefix, suffix, middle_old, middle_new) = @preopt.separate_common_prefix_and_suffix(
    old~,
    new~,
  )
  let edits : Array[Edit[Array[MbtToken]]] = []
  edits.push_iter(@compress.compress_edits(prefix).iter())
  edits.push_iter(
    @compress.compress_piediff_edits(
      old=middle_old,
      new=middle_new,
      @piediff.Diff(old=middle_old, new=middle_new, algorithm=@piediff.Myers).edits,
    ).iter(),
  )
  edits.push_iter(@compress.compress_edits(suffix).iter())
  @postopt.align_edit_boundaries(edits)
}
