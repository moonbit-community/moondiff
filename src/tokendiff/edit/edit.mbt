///|
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Show, ToJson)

///|
pub(all) enum EditKind {
  Ins
  Del
  Eql
} derive(Eq)

///|
pub fn[T] Edit::kind(self : Edit[T]) -> EditKind {
  match self {
    Insert(_) => Ins
    Delete(_) => Del
    Equal(_) => Eql
  }
}
