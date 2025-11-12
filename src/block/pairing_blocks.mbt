///|
pub fn pairing_blocks_by_uuid(
  old~ : ArrayView[Block],
  new~ : ArrayView[Block],
) -> Array[(Block, Block)] raise BlockProcessingError {
  let res : Array[(Block, Block)] = Array::new(
    capacity=old.length() + new.length(),
  )
  let old_uuid = old.map(blk => get_block_uuid(blk))
  let new_uuid = new.map(blk => get_block_uuid(blk))
  let mut old_base = 0
  let mut new_base = 0
  let matched_idx = @unique_lcs.unique_lcs(old=old_uuid, new=new_uuid)
  for pair in matched_idx {
    let delete = old[old_base:pair.0]
    let insert = new[new_base:pair.1]
    for del in delete {
      res.push((del, []))
    }
    for ins in insert {
      res.push(([], ins))
    }
    res.push((old[pair.0], new[pair.1]))
    old_base = pair.0 + 1
    new_base = pair.1 + 1
  } else {
    let delete = old[old_base:]
    let insert = new[new_base:]
    for del in delete {
      res.push((del, []))
    }
    for ins in insert {
      res.push(([], ins))
    }
  }
  res
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
  @json.inspect(
    pairs.map(pair => (
      pair.0.map(triple => triple.0.to_str()),
      pair.1.map(triple => triple.0.to_str()),
    )),
    content=[
      [["///|UUID(1)", "NEWLINE"], []],
      [["///|UUID(2)", "NEWLINE"], []],
      [["///|UUID(3)", "NEWLINE"], ["///|UUID(3)", "NEWLINE"]],
      [["///|UUID(4)", "NEWLINE"], ["///|UUID(4)", "NEWLINE"]],
      [["///|UUID(5)", "EOF"], ["///|UUID(5)", "NEWLINE"]],
      [[], ["///|UUID(6)", "NEWLINE"]],
      [[], ["///|UUID(7)", "EOF"]],
    ],
  )
}
