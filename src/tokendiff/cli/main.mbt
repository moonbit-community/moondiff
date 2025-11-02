///|
typealias @edit.Edit

///|
typealias @mbttoken.MbtToken

///|
fn multiple_block_diff(
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
        let edits = @diff_with_opt.diff_with_opt(old~, new~)
        matching_blocks.push(edits)
      }
    }
  }
  (del_blocks, matching_blocks, ins_blocks)
}

///|
fn rendering_matching_block(
  matching_block : Array[Edit[Array[MbtToken]]],
) -> String {
  let output_buf = OutputBuf::new()
  for edit in matching_block {
    match edit {
      Delete(old~) =>
        for token in old {
          let texts = token.to_text().split_by_newline()
          output_buf.write_texts(Left(texts))
        }
      Insert(new~) =>
        for token in new {
          let texts = token.to_text().split_by_newline()
          output_buf.write_texts(Right(texts))
        }
      Equal(old~, new~) => {
        for token in old {
          let texts = token.to_text().split_by_newline()
          output_buf.write_texts(LeftEql(texts))
        }
        for token in new {
          let texts = token.to_text().split_by_newline()
          output_buf.write_texts(RightEql(texts))
        }
      }
    }
  }
  let (left_str, right_str) = output_buf.output_string()
  let left_lines = left_str.split("\n").collect()
  let right_lines = right_str.split("\n").collect()
  let buf = StringBuilder::new()
  let max_line = left_lines.length().max(right_lines.length())
  for i in 0..<max_line {
    if i < left_lines.length() && !left_lines[i].is_empty() {
      buf.write_stringview(left_lines[i])
    } else {
      buf.write_string(" ".repeat(@config.max_line_width.val))
    }
    buf.write_string(" | ")
    if i < right_lines.length() {
      buf.write_stringview(right_lines[i])
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn do_all(old~ : String, new~ : String) -> Unit raise {
  let (del_blocks, matching_blocks, ins_blocks) = multiple_block_diff(
    old~,
    new~,
  )
  for old in del_blocks {
    println(@chalk.chalk().color(Red).render("--- deleted block \n\n"))
    println(@chalk.chalk().color(Red).render(String::from_array(old)))
    println("")
  }
  for matching_block in matching_blocks {
    let rendered = rendering_matching_block(matching_block)
    println(rendered)
    println("")
  }
  for new in ins_blocks {
    println(@chalk.chalk().color(Green).render("+++ inserted block \n\n"))
    println(@chalk.chalk().color(Green).render(String::from_array(new)))
    println("")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args is [_, old, new] {
    try {
      let old = @fs.read_file_to_string(old)
      let new = @fs.read_file_to_string(new)
      do_all(old~, new~)
    } catch {
      e => println("Error: " + e.to_string())
    }
  }
}
