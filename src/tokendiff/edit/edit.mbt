///|
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Show)

///|
pub impl[T : Show] ToJson for Edit[T] with to_json(self) {
  match self {
    Delete(old~) => { "delete": old.to_string() }
    Insert(new~) => { "insert": new.to_string() }
    Equal(old~, new~) =>
      { "equal": { "old": old.to_string(), "new": new.to_string() } }
  }
}
