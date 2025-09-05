///|
pub fn pairing_blocks_by_uuid(
  old~ : ArrayView[Block],
  new~ : ArrayView[Block],
) -> (Array[Block], Array[(Block, Block)], Array[Block]) raise BlockProcessingError {
  let deleted = Array::new()
  let matched = Array::new()
  let inserted = Array::new()
  let old_table = @hashmap.new(capacity=old.length() * 2)
  for block in old {
    let uuid = get_block_uuid(block)
    old_table[uuid] = block
  }
  let new_table = @hashmap.new(capacity=new.length() * 2)
  let new_uuid_set = @hashset.new(capacity=new.length() * 2)
  for block in new {
    let uuid = get_block_uuid(block)
    new_table[uuid] = block
    new_uuid_set.add(uuid)
  }
  for uuid, block in old_table {
    if new_uuid_set.contains(uuid) {
      matched.push((block, new_table[uuid]))
      new_uuid_set.remove(uuid)
    } else {
      deleted.push(block)
    }
  }
  for uuid in new_uuid_set {
    inserted.push(new_table[uuid])
  }
  return (deleted, matched, inserted)
}
