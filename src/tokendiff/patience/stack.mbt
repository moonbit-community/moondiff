///|
priv struct Stack[T] {
  mut top : T
  mut stack : @list.List[T]
}

///|
fn[T] push(self : Stack[T], t : T) -> Unit {
  self.stack = self.stack.add(self.top)
  self.top = t
}
