///|
pub fn get_block_uuid(blk : Block) -> String raise BlockProcessingError {
  if blk is [head, ..] &&
    head.0 is COMMENT(comment) &&
    comment.content is [.. "///|UUID(", .. rest] &&
    rest is [.. uuid, ')'] {
    return uuid.to_string()
  } else if blk is [head, ..] {
    raise BlockProcessingError::UUIDNotFound("bad delimiter: \{head}")
  } else {
    raise BlockProcessingError::EmptyBlock
  }
}
