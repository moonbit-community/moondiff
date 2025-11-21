///|UUID(506c6efe-832d-479b-ac74-4682c76e2fed)
fn[T : Eq] separate_common_suffix(
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> (Array[Edit[T]], ArrayView[T], ArrayView[T]) {
  let suffix = Array::new(capacity=40)
  loop (old, new) {
    ([] as old_without_prefix, [] as new_without_prefix)
    | ([] as old_without_prefix, new_without_prefix)
    | (old_without_prefix, [] as new_without_prefix) =>
      return (suffix.rev(), old_without_prefix, new_without_prefix)
    (
      [.. old_rest, old_tl] as old_without_prefix,
      [.. new_rest, new_tl] as new_without_prefix,
    ) =>
      if old_tl == new_tl {
        suffix.push(Edit::Equal(old=old_tl, new=new_tl))
        continue (old_rest, new_rest)
      } else {
        return (suffix.rev(), old_without_prefix, new_without_prefix)
      }
  }
}
