///|
priv struct BPArray[T](Array[T]) // BiPolar Array

///|
fn[T] BPArray::make(capacity : Int, default : T) -> BPArray[T] {
  let arr = Array::make(capacity, default)
  BPArray(arr)
}

///|
fn BPArray::copy(self : BPArray[Int]) -> BPArray[Int] {
  let BPArray(arr) = self
  let newarr = Array::make(arr.length(), 0)
  for i = 0; i < arr.length(); i = i + 1 {
    newarr[i] = arr[i]
  } else {
    BPArray(newarr)
  }
}

///|
fn[T] BPArray::op_get(self : BPArray[T], idx : Int) -> T {
  let BPArray(arr) = self
  if idx < 0 {
    arr[arr.length() + idx]
  } else {
    arr[idx]
  }
}

///|
fn[T] BPArray::op_set(self : BPArray[T], idx : Int, elem : T) -> Unit {
  let BPArray(arr) = self
  if idx < 0 {
    arr[arr.length() + idx] = elem
  } else {
    arr[idx] = elem
  }
}
