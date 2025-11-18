///|
pub enum EditBlock {
  Replace(old~ : Block[String], new~ : Block[String])
  Delete(Block[String])
  Insert(Block[String])
} derive(Show, ToJson)

///|
pub fn pairing_blocks_by_uuid(
  old~ : ArrayView[Block[String]],
  new~ : ArrayView[Block[String]],
) -> Array[EditBlock] {
  let result = []
  let new_map = @hashmap.new(capacity=new.length())
  for blk in new {
    new_map[blk.uuid] = blk
  }
  for old_blk in old {
    if new_map.get(old_blk.uuid) is Some(new_blk) {
      new_map.remove(old_blk.uuid)
      result.push(Replace(old=old_blk, new=new_blk))
    } else {
      result.push(Delete(old_blk))
    }
  }
  for _, new_blk in new_map {
    result.push(Insert(new_blk))
  }
  result
}

///|
test {
  let old =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
    #|///|UUID(4)
    #|///|UUID(5)
  let new =
    #|///|UUID(3)
    #|///|UUID(4)
    #|///|UUID(5)
    #|///|UUID(6)
    #|///|UUID(7)
  let old = create_blocks(old)
  let new = create_blocks(new)
  let pairs = pairing_blocks_by_uuid(old~, new~)
  @json.inspect(pairs, content=[
    ["Delete", { "start_line": 1, "uuid": "1", "contents": "" }],
    ["Delete", { "start_line": 2, "uuid": "2", "contents": "" }],
    [
      "Replace",
      {
        "old": { "start_line": 3, "uuid": "3", "contents": "" },
        "new": { "start_line": 1, "uuid": "3", "contents": "" },
      },
    ],
    [
      "Replace",
      {
        "old": { "start_line": 4, "uuid": "4", "contents": "" },
        "new": { "start_line": 2, "uuid": "4", "contents": "" },
      },
    ],
    ["Insert", { "start_line": 3, "uuid": "5", "contents": "" }],
    ["Insert", { "start_line": 4, "uuid": "6", "contents": "" }],
  ])
}
