///|
pub fn create_blocks(
  input : ArrayView[(Token, Position, Position)],
) -> Array[ArrayView[(Token, Position, Position)]] {
  // assume input contains comment
  let res = Array::new(capacity=input.length() / 8)
  let mut prev = 0
  let mut curr = 0
  while curr < input.length() {
    if input[curr].0 is COMMENT(comment) && comment.content == "///|" {
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
    create_blocks(tokens).map(triples => triples.map(triple => triple.0.to_string())),
    content=[
      [
        "COMMENT({content: \"///|\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "NEWLINE", "FN", "LIDENT(\"foo\")", "SEMI(false)", "NEWLINE", "COMMENT({content: \"// comment here\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "NEWLINE",
      ],
      [
        "COMMENT({content: \"///|\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "NEWLINE", "FN", "LIDENT(\"bar\")", "SEMI(false)", "NEWLINE", "COMMENT({content: \"// another comment here\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
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
    create_blocks(tokens).map(triples => triples.map(triple => triple.0.to_string())),
    content=[
      [
        "COMMENT({content: \"///|\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "NEWLINE",
      ],
      [
        "COMMENT({content: \"///|\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "NEWLINE",
      ],
      [
        "COMMENT({content: \"///|\", kind: Ownline(leading_blank_line=false, trailing_blank_line=false), consumed_by_docstring: false})",
        "EOF",
      ],
    ],
  )
}
