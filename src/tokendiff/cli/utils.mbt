///|
fn Array::split_by_newline(self : Array[Char]) -> Array[ArrayView[Char]] {
  let mut prev = 0
  let mut current = 0
  let result = []
  loop self[:] {
    [] => {
      result.push(self[prev:])
      return result
    }
    // moonfmt use '\n', no '\r' && '\r\n' cases
    ['\n', .. rest] => {
      result.push(self[prev:current])
      prev = current + 1
      current = current + 1
      continue rest
    }
    [_, .. rest] => {
      current = current + 1
      continue rest
    }
  }
}

///|
test {
  @json.inspect("foo\nbar\nbaz".to_array().split_by_newline(), content=[
    ["f", "o", "o"],
    ["b", "a", "r"],
    ["b", "a", "z"],
  ])
  @json.inspect("foo\nbar\nbaz\n".to_array().split_by_newline(), content=[
    ["f", "o", "o"],
    ["b", "a", "r"],
    ["b", "a", "z"],
    [],
  ])
  @json.inspect("foo\n\n\nbar".to_array().split_by_newline(), content=[
    ["f", "o", "o"],
    [],
    [],
    ["b", "a", "r"],
  ])
}
