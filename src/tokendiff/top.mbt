///|
pub fn web_multiple_block_diff(
  old~ : String,
  new~ : String,
) -> Array[String] raise Error {
  let old_linewidths = @span.LineWidths::from_str(old)
  let new_linewidths = @span.LineWidths::from_str(new)
  let old = @lexer.tokens_from_string(comment=true, old).tokens
    |> @block.create_blocks
  let new = @lexer.tokens_from_string(comment=true, new).tokens
    |> @block.create_blocks
  let (deleted, matched, inserted) = @block.pairing_blocks_by_uuid(old~, new~)
  let block_edits = Array::new(capacity=matched.length())
  let buf = StringBuilder::new(size_hint=2000)
  for pair in matched {
    let old = @mbttoken.MbtToken::from_triples(pair.0, old_linewidths)
    let new = @mbttoken.MbtToken::from_triples(pair.1, new_linewidths)
    let edits = @diff.diff_with_opt(old~, new~)
    buf.reset()
    @render.web_rendering(buf, edits)
    block_edits.push(buf.to_string())
  } else {
    return block_edits
  }
}
