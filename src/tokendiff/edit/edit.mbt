///|UUID(4b11b6dc-b16a-4fe1-85dd-c9196ea962d7)
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Debug)
