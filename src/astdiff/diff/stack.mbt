///|UUID(db3b80c2-5673-4e03-8acb-478ba009c852)
struct Node[T] {
  val : T
  next : Node[T]?
}

///|UUID(1abc1ea8-aa15-4919-aa1c-126e2860d439)
/// A persistent stack.
///
/// This is similar to `Stack` from the rpds crate, but it's faster
/// and uses less memory.
pub struct Stack[T](Node[T]?)

///|UUID(ccb74e09-ee80-4917-9bf2-814ebbe7325a)
pub fn[T] Stack::new() -> Stack[T] {
  Stack(None)
}

///|UUID(b7c6ae40-0b9a-4021-aee5-673ecab1ee4b)
pub fn[T] Stack::push(self : Stack[T], val : T) -> Stack[T] {
  Stack(Some(Node::{ val, next: self.0 }))
}

///|UUID(6f8f8232-5a83-4152-a372-ebd14e8a504c)
pub fn[T] Stack::pop(self : Stack[T]) -> Stack[T]? {
  self.0.map(node => Stack(node.next))
}

///|UUID(88f4f244-721d-42e0-9d6f-2911ff8531c4)
pub fn[T] Stack::peek(self : Stack[T]) -> T? {
  self.0.map(node => node.val)
}

///|UUID(5607dc9b-cdc2-4f40-923e-fc0891e0e5c6)
pub fn[T] Stack::size(self : Stack[T]) -> UInt {
  let mut count = 0U
  let mut stack = self
  while stack is Stack(Some(node)) {
    count += 1
    stack = Stack(node.next)
  }
  count
}

///|UUID(f68bcad4-677c-42d0-9ea2-849a330e15f8)
pub fn[T] Stack::is_empty(self : Stack[T]) -> Bool {
  self.0 is None
}
