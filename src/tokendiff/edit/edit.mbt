///|UUID(b425588a-4f84-41d0-ace5-b7dc465b41a4)
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Debug)
