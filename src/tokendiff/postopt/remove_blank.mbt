///|
fn Array::remove_leading_trailing_blank(
  self : Array[Edit[Array[MbtToken]]],
) -> Array[Edit[Array[MbtToken]]] {
  let result = Array::new(capacity=self.length() * 3 / 2)
  for edit in self {
    match result {
      [] => result.push(edit)
      [.., last] =>
        match (last, edit) {
          // try eliminate leading invisible token in delete
          (Equal(new~, old=hd), Delete(old=tl)) if tl
            is [Invisible(_) as blank, .. rest] => {
            result.truncate(result.length() - 1)
            result.push(Equal(new~, old=hd + [blank]))
            result.push(Delete(old=rest.to_array()))
          }
          // try eliminate trailing invisible token in delete
          (Delete(old=hd), Equal(new~, old=tl)) if hd
            is [.. rest, Invisible(_) as blank] => {
            result.truncate(result.length() - 1)
            result.push(Delete(old=rest.to_array()))
            result.push(Equal(new~, old=[blank] + tl))
          }
          // try eliminate leading invisible token in insert
          (Equal(new=hd, old~), Insert(new=tl)) if tl
            is [Invisible(_) as blank, .. rest] => {
            result.truncate(result.length() - 1)
            result.push(Equal(new=hd + [blank], old~))
            result.push(Insert(new=rest.to_array()))
          }
          //try eliminate trailing invisible token in insert
          (Insert(new=hd), Equal(new=tl, old~)) if hd
            is [.. rest, Invisible(_) as blank] => {
            result.truncate(result.length() - 1)
            result.push(Insert(new=rest.to_array()))
            result.push(Equal(new=[blank] + tl, old~))
          }
          // eliminate leading/trailing invisible token in delete followed by insert
          (Delete(old~), Insert(new~)) =>
            if old is [.. rest, Invisible(_) as blank] {
              result.truncate(result.length() - 1)
              result.push(Delete(old=rest.to_array()))
              result.push(Equal(old=[blank], new=[]))
              result.push(edit)
            } else if new is [Invisible(_) as blank, .. rest] {
              result.push(Equal(old=[], new=[blank]))
              result.push(Insert(new=rest.to_array()))
            } else {
              result.push(edit)
            }
          // eliminate leading/trailing invisible token in insert followed by delete
          (Insert(new~), Delete(old~)) =>
            if old is [Invisible(_) as blank, .. rest] {
              result.push(Equal(old=[blank], new=[]))
              result.push(Delete(old=rest.to_array()))
            } else if new is [.. rest, Invisible(_) as blank] {
              result.truncate(result.length() - 1)
              result.push(Insert(new=rest.to_array()))
              result.push(Equal(old=[], new=[blank]))
              result.push(edit)
            } else {
              result.push(edit)
            }
          _ => result.push(edit)
        }
    }
  } else {
    return result
  }
}
