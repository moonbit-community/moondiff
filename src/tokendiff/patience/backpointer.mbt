///|
priv struct BackPointer[T] {
  value : T
  prev : BackPointer[T]?
}

///|
fn[T] to_array(self : BackPointer[T]) -> Array[T] {
  match self.prev {
    None => [self.value]
    Some(prev) => {
      let prev = prev.to_array()
      prev.push(self.value)
      return prev
    }
  }
}
