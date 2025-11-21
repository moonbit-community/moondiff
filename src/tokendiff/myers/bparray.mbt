///|UUID(80926b47-7ddb-4891-84c8-5af8724cb9ab)
priv struct BPArray[T](Array[T]) // BiPolar Array

///|UUID(8955555b-ead8-4f66-9866-14246c787c18)
fn[T] BPArray::make(capacity : Int, default : T) -> BPArray[T] {
  let arr = Array::make(capacity, default)
  BPArray(arr)
}

///|UUID(d3536d42-afe4-46a7-aabd-4a68c83e8045)
fn BPArray::copy(self : BPArray[Int]) -> BPArray[Int] {
  let BPArray(arr) = self
  let newarr = Array::make(arr.length(), 0)
  for i = 0; i < arr.length(); i = i + 1 {
    newarr[i] = arr[i]
  } else {
    BPArray(newarr)
  }
}

///|UUID(078042c3-3936-4762-9915-d98f0fab81e7)
fn[T] BPArray::op_get(self : BPArray[T], idx : Int) -> T {
  let BPArray(arr) = self
  if idx < 0 {
    arr[arr.length() + idx]
  } else {
    arr[idx]
  }
}

///|UUID(8c80b721-c1a8-4a19-a156-534c2b1d91b0)
fn[T] BPArray::op_set(self : BPArray[T], idx : Int, elem : T) -> Unit {
  let BPArray(arr) = self
  if idx < 0 {
    arr[arr.length() + idx] = elem
  } else {
    arr[idx] = elem
  }
}
