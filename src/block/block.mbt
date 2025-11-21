///|UUID(7ede3596-5ea0-45c8-bc14-d28380fe229a)
pub struct Block[T] {
  start_line : Int
  uuid : String
  contents : T
} derive(Show, ToJson)
