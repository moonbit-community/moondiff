///|UUID(ca1838d0-b11e-46bf-987c-5e3d7d08c6de)
pub enum REdit {
  Normal(@edit.Edit[Array[StringView]])
  Replace(old~ : Array[StringView], new~ : Array[StringView])
} derive(ToJson)

///|UUID(e9c1b971-0da7-425d-87f6-520910e5a22b)
pub fn line_group(old : String, new : String) -> Array[REdit] {
  let groups = Array::new()
  let mut old = old.split("\n").collect()[:]
  while old is [.. rest, ""] {
    old = rest
  }
  let mut new = new.split("\n").collect()[:]
  while new is [.. rest, ""] {
    new = rest
  }
  let mut edits = @compress.compress_edits(@myers.diff(old~, new~))[:]
  if edits
    is ([Delete(old~), Insert(new~), .. rest]
    | [Insert(new~), Delete(old~), .. rest]) {
    groups.push(REdit::Replace(old~, new~))
    edits = rest
  }
  while true {
    match edits {
      [] => break
      [Delete(old~), Insert(new~)] | [Insert(new~), Delete(old~)] => {
        groups.push(REdit::Replace(old~, new~))
        break
      }
      [Equal(..) as prev, Insert(new~), Delete(old~), .. rest]
      | [Equal(..) as prev, Delete(old~), Insert(new~), .. rest] => {
        groups.push(REdit::Normal(prev))
        groups.push(REdit::Replace(old~, new~))
        edits = rest
      }
      [edit, .. rest] => {
        groups.push(REdit::Normal(edit))
        edits = rest
      }
    }
  }
  return groups
}

///|UUID(b7cdcb24-ce84-474e-9dfa-9a7ea0d7af02)
test {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
    #|quux
  let new =
    #|foo
    #|bar
    #|BAZ
    #|QUX
    #|quux
  let groups = line_group(old, new)
  @json.inspect(groups, content=[
    ["Normal", { "equal": { "old": ["foo", "bar"], "new": ["foo", "bar"] } }],
    ["Replace", { "old": ["baz", "qux"], "new": ["BAZ", "QUX"] }],
    ["Normal", { "equal": { "old": ["quux"], "new": ["quux"] } }],
  ])
  let old =
    #|alpha
    #|beta
    #|gamma
    #|delta
  let new =
    #|ALPHA
    #|beta
    #|epsilon
    #|gamma
    #|DELTA
  let groups = line_group(old, new)
  @json.inspect(groups, content=[
    ["Replace", { "old": ["alpha"], "new": ["ALPHA"] }],
    ["Normal", { "equal": { "old": ["beta"], "new": ["beta"] } }],
    ["Normal", { "insert": ["epsilon"] }],
    ["Normal", { "equal": { "old": ["gamma"], "new": ["gamma"] } }],
    ["Replace", { "old": ["delta"], "new": ["DELTA"] }],
  ])
}
