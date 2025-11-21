///|UUID(b425588a-4f84-41d0-ace5-b7dc465b41a4)
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Show)

///|UUID(fc200a4e-5f2b-4ded-be2d-908e26dabbae)
pub impl[T : Show] ToJson for Edit[T] with to_json(self) {
  match self {
    Delete(old~) => { "delete": old.to_string() }
    Insert(new~) => { "insert": new.to_string() }
    Equal(old~, new~) =>
      { "equal": { "old": old.to_string(), "new": new.to_string() } }
  }
}
