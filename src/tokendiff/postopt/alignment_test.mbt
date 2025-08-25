///|
typealias @edit.Edit

///|
test "single delete move forward" {
  let edits : Array[Edit[Array[Char]]] = [
    Equal(new=['T', 'h'], old=[]),
    Delete(old=['a', 't', ' ', 'c']),
    Equal(new=['a', 't', ' ', 'c', 'a', 'r', 't', 'o', 'o', 'n'], old=[]),
  ]
  @json.inspect(align_edit_boundaries(edits), content=[
    ["Equal", [], ["T", "h", "a", "t"]],
    ["Delete", [" ", "c", "a", "t"]],
    ["Equal", [], [" ", "c", "a", "r", "t", "o", "o", "n"]],
  ])
}

///|
test "single insert move forward" {
  let edits : Array[Edit[Array[Char]]] = [
    Equal(new=['T', 'h'], old=[]),
    Insert(new=['a', 't', ' ', 'c']),
    Equal(new=['a', 't', ' ', 'c', 'a', 'r', 't', 'o', 'o', 'n'], old=[]),
  ]
  @json.inspect(align_edit_boundaries(edits), content=[
    ["Equal", [], ["T", "h", "a", "t"]],
    ["Insert", [" ", "c", "a", "t"]],
    ["Equal", [], [" ", "c", "a", "r", "t", "o", "o", "n"]],
  ])
}

///|
test "single delete move backward" {
  let edits : Array[Edit[Array[Char]]] = [
    Equal(new=['h', 'e'], old=[]),
    Delete(old=['l', 'l', 'o', ' ', 'h', 'e']),
    Equal(new=['l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd'], old=[]),
  ]
  @json.inspect(align_edit_boundaries(edits), content=[
    ["Equal", [], []],
    ["Delete", ["h", "e", "l", "l", "o", " "]],
    ["Equal", [], ["h", "e", "l", "l", "o", " ", "W", "o", "r", "l", "d"]],
  ])
}

///|
test "fn insert errorpoly" {
  let edits : Array[Edit[Array[Char]]] = [
    Equal(new=[')', ' ', '-', '>', ' ', 'U'], old=[]),
    Insert(new=['?', ' ', 'r', 'a', 'i', 's', 'e']),
    Equal(new=['?', ' ', '{'], old=[]),
  ]
  @json.inspect(align_edit_boundaries(edits), content=[
    ["Equal", [], ["-", ">", " ", "U", "?"]],
    ["Insert", [" ", "r", "a", "i", "s", "e", "?"]],
    ["Equal", [], [" ", "{"]],
  ])
}
