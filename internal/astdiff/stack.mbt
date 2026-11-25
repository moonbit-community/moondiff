///|UUID(1abc1ea8-aa15-4919-aa1c-126e2860d439)
/// A persistent stack.
#derive(Eq)
pub struct Stack[T](@list.List[T])

///|UUID(ccb74e09-ee80-4917-9bf2-814ebbe7325a)
pub fn[T] Stack::new() -> Stack[T] {
  Stack(@list.List([]))
}

///|UUID(b7c6ae40-0b9a-4021-aee5-673ecab1ee4b)
pub fn[T] Stack::push(self : Stack[T], val : T) -> Stack[T] {
  Stack(self.0.prepend(val))
}

///|UUID(6f8f8232-5a83-4152-a372-ebd14e8a504c)
pub fn[T] Stack::pop(self : Stack[T]) -> Stack[T]? {
  match self.0 {
    Empty => None
    More(_, tail~) => Some(Stack(tail))
  }
}

///|UUID(88f4f244-721d-42e0-9d6f-2911ff8531c4)
pub fn[T] Stack::peek(self : Stack[T]) -> T? {
  self.0.head()
}

///|UUID(5607dc9b-cdc2-4f40-923e-fc0891e0e5c6)
pub fn[T] Stack::size(self : Stack[T]) -> UInt32 {
  self.0.length().reinterpret_as_uint()
}

///|UUID(f68bcad4-677c-42d0-9ea2-849a330e15f8)
pub fn[T] Stack::is_empty(self : Stack[T]) -> Bool {
  self.0.is_empty()
}
