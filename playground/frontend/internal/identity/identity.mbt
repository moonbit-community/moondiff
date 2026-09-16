///|
/// Identity of an immutable snapshot; never walks its contents.
pub fn[T] same(left : T, right : T) -> Bool {
  physical_equal(left, right)
}

///|
pub fn[T] same_option(left : T?, right : T?) -> Bool {
  match (left, right) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => true
    _ => false
  }
}
