///|
pub type Blocks[T] = Array[Block[T]]

///|
pub fn create_blocks(
  input : ArrayView[(Token, Position, Position)],
) -> Blocks[ArrayView[(Token, Position, Position)]] raise BlockProcessingError {
  // assume input contains comment
  let res = Array::new(capacity=input.length() / 8)
  let mut prev = 0
  let mut curr = 0
  while curr < input.length() {
    if input[curr].0 is COMMENT(comment) && comment.content.has_prefix("///|") {
      if curr != 0 {
        let contents = input[prev:curr]
        let start_line = contents[0].1.lnum
        let uuid = Block::get_block_uuid(contents)
        res.push(Block::{ start_line, uuid, contents })
      }
      prev = curr
    }
    curr += 1
  }
  if prev != curr {
    let contents = input[prev:curr]
    let start_line = contents[0].1.lnum
    let uuid = Block::get_block_uuid(contents)
    res.push(Block::{ start_line, uuid, contents })
  }
  return res
}

///|
test {
  let text =
    #|///|UUID(1)
    #|fn foo
    #|  // comment here
    #|///|UUID(2)
    #|fn bar
    #|  // another comment here
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  // TODO
}

///|
test "empty block" {
  let text =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  // TODO
  let text =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
    #|///|UUID(4)
    #|///|UUID(5)
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  // TODO
}
