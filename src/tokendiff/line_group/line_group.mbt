///|
pub enum REdit {
  Normal(@edit.Edit[Array[StringView]])
  Replace(old~ : Array[StringView], new~ : Array[StringView])
} derive(ToJson)

///|
pub fn line_group(old : String, new : String) -> Array[REdit] {
  let groups = Array::new()
  let old = old.split("\n").collect()[:]
  let new = new.split("\n").collect()[:]
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
      [
        Equal(..) as prev,
        Insert(new~),
        Delete(old~),
        Equal(..) as next,
        .. rest,
      ]
      | [
        Equal(..) as prev,
        Delete(old~),
        Insert(new~),
        Equal(..) as next,
        .. rest,
      ] => {
        groups.push(REdit::Normal(prev))
        groups.push(REdit::Replace(old~, new~))
        groups.push(REdit::Normal(next))
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

///|
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
    [
      "Normal",
      { "equal": { "old": "[\"foo\", \"bar\"]", "new": "[\"foo\", \"bar\"]" } },
    ],
    ["Replace", { "old": ["baz", "qux"], "new": ["BAZ", "QUX"] }],
    ["Normal", { "equal": { "old": "[\"quux\"]", "new": "[\"quux\"]" } }],
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
    ["Normal", { "equal": { "old": "[\"beta\"]", "new": "[\"beta\"]" } }],
    ["Normal", { "insert": "[\"epsilon\"]" }],
    ["Normal", { "equal": { "old": "[\"gamma\"]", "new": "[\"gamma\"]" } }],
    ["Replace", { "old": ["delta"], "new": ["DELTA"] }],
  ])
}
