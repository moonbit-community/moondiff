///|UUID(78e6e490-9634-4f13-9756-2a31b9369189)
fn separate_common_prefix(
  old~ : ArrayView[MbtToken],
  new~ : ArrayView[MbtToken],
) -> (Array[Edit[MbtToken]], ArrayView[MbtToken], ArrayView[MbtToken]) {
  let prefix = Array::new(capacity=40)
  loop (old, new) {
    ([] as old_without_prefix, [] as new_without_prefix)
    | ([] as old_without_prefix, new_without_prefix)
    | (old_without_prefix, [] as new_without_prefix) =>
      return (prefix, old_without_prefix, new_without_prefix)
    (
      [old_hd, .. old_rest] as old_without_prefix,
      [new_hd, .. new_rest] as new_without_prefix,
    ) =>
      if old_hd == new_hd {
        prefix.push(Edit::Equal(old=old_hd, new=new_hd))
        continue (old_rest, new_rest)
      } else {
        return (prefix, old_without_prefix, new_without_prefix)
      }
  }
}
