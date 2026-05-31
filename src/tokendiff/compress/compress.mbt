///|UUID(c5d0ea5e-8380-4da0-9805-eec7d838460e)
pub fn[T] compress_edits(edits : ArrayView[Edit[T]]) -> Array[Edit[Array[T]]] {
  let compressed = []
  for edit in edits {
    match edit {
      Delete(old~) => compressed.push_chunk_edit(Delete(old=[old]))
      Insert(new~) => compressed.push_chunk_edit(Insert(new=[new]))
      Equal(new~, old~) =>
        compressed.push_chunk_edit(Equal(new=[new], old=[old]))
    }
  }
  compressed
}

///|UUID(c421b28f-5c25-48bd-9246-c583dcf007ba)
pub fn[T] compress_piediff_edits(
  old~ : ArrayView[T],
  new~ : ArrayView[T],
  edits : ArrayView[@piediff.Edit],
) -> Array[Edit[Array[T]]] {
  let compressed = []
  for edit in edits {
    match edit {
      @piediff.Edit::Delete(old_index~, len~, ..) =>
        if len > 0 {
          compressed.push(
            Edit::Delete(
              old=old.view(start=old_index, end=old_index + len).to_owned(),
            ),
          )
        }
      @piediff.Edit::Insert(new_index~, len~, ..) =>
        if len > 0 {
          compressed.push(
            Edit::Insert(
              new=new.view(start=new_index, end=new_index + len).to_owned(),
            ),
          )
        }
      @piediff.Edit::Equal(old_index~, new_index~, len~) =>
        if len > 0 {
          compressed.push(
            Edit::Equal(
              old=old.view(start=old_index, end=old_index + len).to_owned(),
              new=new.view(start=new_index, end=new_index + len).to_owned(),
            ),
          )
        }
    }
  }
  compressed
}

///|UUID(6ff5191f-f39f-4783-ac39-cde3dfad88e4)
fn[T] Array::push_chunk_edit(
  self : Array[Edit[Array[T]]],
  edit : Edit[Array[T]],
) -> Unit {
  match self {
    [] => self.push(edit)
    [.., last] =>
      match (last, edit) {
        (Delete(old=hd), Delete(old=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Delete(old=hd + tl))
        }
        (Insert(new=hd), Insert(new=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Insert(new=hd + tl))
        }
        (Equal(new=hd, old=old_hd), Equal(new=tl, old=old_tl)) => {
          self.truncate(self.length() - 1)
          self.push(Equal(new=hd + tl, old=old_hd + old_tl))
        }
        _ => self.push(edit)
      }
  }
}
