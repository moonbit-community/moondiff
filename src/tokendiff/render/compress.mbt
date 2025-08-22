///|
priv enum EditKind {
  Ins
  Del
  Eql
} derive(Eq)

///|
fn compress_edits(
  edits : ArrayView[Edit[MbtToken]],
) -> Array[Edit[Array[Char]]] {
  fn kind_of(edit : Edit[MbtToken]) -> EditKind {
    match edit {
      Edit::Insert(_) => Ins
      Edit::Delete(_) => Del
      Edit::Equal(_) => Eql
    }
  }

  let mut buf = []
  let result = Array::new(capacity=edits.length())
  let mut prev_kind = Eql
  for edit in edits {
    let kind = kind_of(edit)
    if kind != prev_kind {
      if !buf.is_empty() {
        match prev_kind {
          Ins => result.push(Edit::Insert(new=buf))
          Del => result.push(Edit::Delete(old=buf))
          Eql => result.push(Edit::Equal(new=buf, old=[]))
        }
        buf = []
      }
      prev_kind = kind
    }
    let tok = match edit {
      Edit::Insert(new~) => new
      Edit::Delete(old~) => old
      Edit::Equal(new~, ..) => new
    }
    buf.append(tok.get_unicodes())
  } else {
    if !buf.is_empty() {
      match prev_kind {
        Ins => result.push(Edit::Insert(new=buf))
        Del => result.push(Edit::Delete(old=buf))
        Eql => result.push(Edit::Equal(new=buf, old=[]))
      }
    }
    result
  }
}
