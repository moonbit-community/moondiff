///|
pub type Blocks = Array[Block]

///|
pub fn create_blocks(input : ArrayView[(Token, Position, Position)]) -> Blocks {
  // assume input contains comment
  let res = Array::new(capacity=input.length() / 8)
  let mut prev = 0
  let mut curr = 0
  while curr < input.length() {
    if input[curr].0 is COMMENT(comment) && comment.content.has_prefix("///|") {
      if curr != 0 {
        res.push(input[prev:curr])
      }
      prev = curr
    }
    curr += 1
  }
  if prev != curr {
    res.push(input[prev:curr])
  }
  return res
}

///|
fn Token::to_str(self : Token) -> String {
  match self {
    COMMENT(comment) => comment.content
    other => other.to_string()
  }
}

///|
test {
  let text =
    #|///|
    #|fn foo
    #|  // comment here
    #|///|
    #|fn bar
    #|  // another comment here
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  @json.inspect(
    create_blocks(tokens).map(block => block.map(triple => triple.0.to_str())),
    content=[
      [
        "///|", "NEWLINE", "FN", "LIDENT(\"foo\")", "SEMI(false)", "NEWLINE", "// comment here",
        "NEWLINE",
      ],
      [
        "///|", "NEWLINE", "FN", "LIDENT(\"bar\")", "SEMI(false)", "NEWLINE", "// another comment here",
        "EOF",
      ],
    ],
  )
}

///|
test "empty block" {
  let text =
    #|///|
    #|///|
    #|///|
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  @json.inspect(
    create_blocks(tokens).map(block => block.map(triple => triple.0.to_str())),
    content=[["///|", "NEWLINE"], ["///|", "NEWLINE"], ["///|", "EOF"]],
  )
  let text =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
    #|///|UUID(4)
    #|///|UUID(5)
  let tokens = @lexer.tokens_from_string(comment=true, text).tokens
  @json.inspect(
    create_blocks(tokens).map(block => block.map(triple => triple.0.to_str())),
    content=[
      ["///|UUID(1)", "NEWLINE"],
      ["///|UUID(2)", "NEWLINE"],
      ["///|UUID(3)", "NEWLINE"],
      ["///|UUID(4)", "NEWLINE"],
      ["///|UUID(5)", "EOF"],
    ],
  )
}
