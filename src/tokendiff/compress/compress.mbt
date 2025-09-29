///|

///|
pub fn compress_edits(
  edits : ArrayView[Edit[MbtToken]],
) -> Array[Edit[Array[MbtToken]]] {
  let compressed : Array[Edit[Array[MbtToken]]] = []
  for edit in edits {
    compressed.push_edit(edit)
  }
  compressed
}

///|
fn Array::push_edit(
  self : Array[Edit[Array[MbtToken]]],
  edit : Edit[MbtToken],
) -> Unit {
  match self {
    [] =>
      match edit {
        Delete(old~) => self.push(Delete(old=[old]))
        Insert(new~) => self.push(Insert(new=[new]))
        Equal(new~, old~) => self.push(Equal(new=[new], old=[old]))
      }
    [.., last] =>
      match (last, edit) {
        (Delete(old=hd), Delete(old=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Delete(old=hd + [tl]))
        }
        (Insert(new=hd), Insert(new=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Insert(new=hd + [tl]))
        }
        (Equal(new=hd, old=old_hd), Equal(new=tl, old=old_tl)) => {
          self.truncate(self.length() - 1)
          self.push(Equal(new=hd + [tl], old=old_hd + [old_tl]))
        }
        (_, Delete(old~)) => self.push(Delete(old=[old]))
        (_, Insert(new~)) => self.push(Insert(new=[new]))
        (_, Equal(new~, old~)) => self.push(Equal(new=[new], old=[old]))
      }
  }
  // 
}
