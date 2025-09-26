///|
typealias @edit.Edit

///|
typealias @mbttoken.MbtToken

///|
pub fn web_multiple_block_diff(
  old~ : String,
  new~ : String,
) -> (
  Array[Array[Char]],
  Array[Array[Edit[Array[MbtToken]]]],
  Array[Array[Char]],
) raise Error {
  let old_linewidths = @span.LineWidths::from_str(old)
  let new_linewidths = @span.LineWidths::from_str(new)
  let old = @lexer.tokens_from_string(comment=true, old).tokens
    |> @block.create_blocks
  let new = @lexer.tokens_from_string(comment=true, new).tokens
    |> @block.create_blocks
  let pairs = @block.pairing_blocks_by_uuid(old~, new~)
  let del_blocks = []
  let ins_blocks = []
  let matching_blocks = []
  for pair in pairs {
    match pair {
      (blk, []) => {
        let (start_pos, end_pos) = if blk.length() == 0 {
          continue
        } else {
          (blk[0].1, blk[blk.length() - 1].2)
        }
        let old = old_linewidths.text_of_loc(start_pos, end_pos)
        del_blocks.push(old)
      }
      ([], blk) => {
        let (start_pos, end_pos) = if blk.length() == 0 {
          continue
        } else {
          (blk[0].1, blk[blk.length() - 1].2)
        }
        let new = new_linewidths.text_of_loc(start_pos, end_pos)
        ins_blocks.push(new)
      }
      (old, new) => {
        let old = @mbttoken.MbtToken::from_triples(old, old_linewidths)
        let new = @mbttoken.MbtToken::from_triples(new, new_linewidths)
        let edits = @diff.diff_with_opt(old~, new~)
        matching_blocks.push(edits)
      }
    }
  }
  (del_blocks, matching_blocks, ins_blocks)
}
