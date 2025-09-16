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
  let pairs = @block.pairing_blocks_by_uuid(old~, new~)
  let block_edits = Array::new(capacity=pairs.length())
  let buf = StringBuilder::new(size_hint=2000)
  for pair in pairs {
    match pair {
      (blk, []) => {
        let (start_pos, end_pos) = if blk.length() == 0 {
          continue
        } else {
          (blk[0].1, blk[blk.length() - 1].2)
        }
        let old = old_linewidths.text_of_loc(start_pos, end_pos)
        buf.reset()
        @render.web_rendering_delete_block(buf, old~)
        block_edits.push(buf.to_string())
      }
      ([], blk) => {
        let (start_pos, end_pos) = if blk.length() == 0 {
          continue
        } else {
          (blk[0].1, blk[blk.length() - 1].2)
        }
        let new = new_linewidths.text_of_loc(start_pos, end_pos)
        buf.reset()
        @render.web_rendering_insert_block(buf, new~)
        block_edits.push(buf.to_string())
      }
      (old, new) => {
        let old = @mbttoken.MbtToken::from_triples(old, old_linewidths)
        let new = @mbttoken.MbtToken::from_triples(new, new_linewidths)
        let edits = @diff.diff_with_opt(old~, new~)
        buf.reset()
        @render.web_rendering(buf, edits)
        block_edits.push(buf.to_string())
      }
    }
  }
  return block_edits
}
