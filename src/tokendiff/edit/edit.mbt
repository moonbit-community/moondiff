///|
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Show)

///|
pub impl[T : Show] ToJson for Edit[T] with to_json(self) {
  match self {
    Delete(old~) => "--- \{old}"
    Insert(new~) => "+++ \{new}"
    Equal(old~, new~) => ["%%% \{old}", "%%% \{new}"]
  }
}
