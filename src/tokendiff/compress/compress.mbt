///|

///|UUID(8ca9d984-857a-42bf-8152-eee4d851c8b8)
pub fn[T] compress_edits(edits : ArrayView[Edit[T]]) -> Array[Edit[Array[T]]] {
  let compressed : Array[Edit[Array[T]]] = []
  for edit in edits {
    compressed.push_edit(edit)
  }
  compressed
}

///|UUID(a2e41142-b501-4691-9c28-d0c774fdc022)
fn[T] Array::push_edit(self : Array[Edit[Array[T]]], edit : Edit[T]) -> Unit {
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
