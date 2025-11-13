///|
pub fn Block::get_block_uuid(
  self : ArrayView[(Token, Position, Position)],
) -> String raise BlockProcessingError {
  if self is [head, ..] &&
    head.0 is COMMENT(comment) &&
    comment.content is [.. "///|UUID(", .. rest] &&
    rest is [.. uuid, ')'] {
    return uuid.to_string()
  } else if self is [head, ..] {
    raise BlockProcessingError::UUIDNotFound("bad delimiter: \{head}")
  } else {
    raise BlockProcessingError::EmptyBlock
  }
}
