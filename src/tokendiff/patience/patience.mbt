///|
pub fn[T : Eq + Hash] patience_diff(
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> Array[Edit[T]] {
  let mut old_base = 0
  let mut new_base = 0
  let split_points = longest_increasing_subsequence(find_unique(old~, new~))
  let edits = Array::new(capacity=old.length() + new.length())
  for pair in split_points.iter() {
    let (old_i, new_i) = pair
    let subedits = @myers.diff(old=old[old_base:old_i], new=new[new_base:new_i])
    edits.append(subedits)
    old_base = old_i
    new_base = new_i
  } else {
    let subedits = @myers.diff(old=old[old_base:], new=new[new_base:])
    edits.append(subedits)
  }
  return edits
}
