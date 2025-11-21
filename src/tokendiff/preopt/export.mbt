///|UUID(984694cc-a0d3-4fbe-bf35-cba07d6f5408)
pub fn[T : Eq] separate_common_prefix_and_suffix(
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> (ArrayView[Edit[T]], ArrayView[Edit[T]], ArrayView[T], ArrayView[T]) {
  let (prefix, old, new) = separate_common_prefix(old~, new~)
  let (suffix, old, new) = separate_common_suffix(old~, new~)
  return (prefix, suffix, old, new)
}
