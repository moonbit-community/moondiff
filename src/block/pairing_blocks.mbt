///|
pub enum EditBlock {
  Replace(
    old~ : Block[ArrayView[(Token, Position, Position)]],
    new~ : Block[ArrayView[(Token, Position, Position)]]
  )
  Delete(Block[ArrayView[(Token, Position, Position)]])
  Insert(Block[ArrayView[(Token, Position, Position)]])
}

///|
pub fn pairing_blocks_by_uuid(
  old~ : ArrayView[Block[ArrayView[(Token, Position, Position)]]],
  new~ : ArrayView[Block[ArrayView[(Token, Position, Position)]]],
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
  let old = create_blocks(@lexer.tokens_from_string(comment=true, old).tokens)
  let new = create_blocks(@lexer.tokens_from_string(comment=true, new).tokens)
  let pairs = pairing_blocks_by_uuid(old~, new~)
  // TODO
}
