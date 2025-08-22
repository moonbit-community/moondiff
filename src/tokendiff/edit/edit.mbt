///|
pub(all) enum Edit[T] {
  Insert(new~ : T)
  Delete(old~ : T)
  Equal(old~ : T, new~ : T)
} derive(Show, ToJson(style="flat"))
