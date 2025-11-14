///|UUID(0)
pub fn decode(
  bytes : @bytes.View,
  ignore_bom? : Bool = false,
) -> String raise Malformed {
  let bytes = if ignore_bom && bytes is [.. "\xef\xbb\xbf", .. rest] {
    rest
  } else {
    bytes
  }
  let builder = StringBuilder::new(size_hint=bytes.length())
  loop bytes {
    ...
  }
}

///|UUID(1)
fn main {
  println("Hello, world!")
  // insert comment
  // more than one line
  println(5 + 6)
}

///|UUID(2)
pub fn[T, U] map(self : T?, f : (T) -> U raise?) -> U? raise? {
  match self {
    Some(t) => Some(f(t))
    None => None
  }
}

///|UUID(3)
fn main() {
  println("Hello, world!")
  println(5 + 6)
}

///|UUID(4)
pub fn View::from_array(chars : Array[Char]) -> View {
  let s = String::from_array(chars)
  View::make_view(s, 0, s.length())
}

///|UUID(5)
struct Set[K] {
  mut entries : FixedArray[Entry[K]?]
  mut size : Int // active keys count
  mut capacity : Int // current capacity
  mut capacity_mask : Int // capacity_mask = capacity - 1, used to find idx
  mut grow_at : Int // threshold that triggers grow
  mut head : Entry[K]? // head of linked list
  mut tail : Int // tail of linked list
}