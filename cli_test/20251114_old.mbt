///|UUID(0)
pub fn decode(bytes : @bytes.View) -> String raise Malformed {
  let builder = StringBuilder::new(size_hint=bytes.length())
  loop bytes {
    ...
  }
}

///|UUID(1)
fn main {
  println("Hello, world!")
  println(5 + 6)
}

///|UUID(2)
pub fn[T, U] map(self : T?, f : (T) -> U) -> U? {
  match self {
    Some(t) => Some(f(t))
    None => None
  }
}

///|UUID(3)
fn main() {
  println(
    "Hello, world!"
  )
}

///|UUID(4)
pub fn View::from_array(chars : Array[Char]) -> View {
  // todo: remove .view() in new version
  String::from_array(chars).view()
}

///|UUID(5)
struct Set[K] {
  mut entries : FixedArray[SEntry[K]?]
  mut list : FixedArray[SListNode[K]]
  mut size : Int
  mut capacity : Int
  mut capacity_mask : Int
  mut grow_at : Int
  mut head : SEntry[K]?
  mut tail : SEntry[K]?
}