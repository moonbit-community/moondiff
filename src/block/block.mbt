///|
pub struct Block[T] {
  start_line : Int
  uuid : String
  contents : T
} derive(Show, ToJson)
