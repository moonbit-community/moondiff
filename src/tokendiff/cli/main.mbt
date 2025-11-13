///|
using @edit {type Edit}

///|
using @mbttoken {type MbtToken}

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
fn split_matching_block(
  matching_block : Array[Edit[Array[MbtToken]]],
) -> (Array[Array[(Bool, Array[Char])]], Array[Array[(Bool, Array[Char])]]) {
  let left = []
  let right = []
  let current_line_left = Ref::new([])
  let current_line_right = Ref::new([])
  fn process_edits(
    old : Array[MbtToken],
    modified : Bool,
    current_line : Ref[Array[(Bool, Array[Char])]],
    full : Array[Array[(Bool, Array[Char])]],
  ) -> Unit {
    if old.search_by(tok => tok is Invisible(widths) && widths.contains(0))
      is None {
      let buf = Array::new()
      for token in old {
        buf.append(token.to_text())
      }
      current_line.val.push((modified, buf))
    } else {
      let mut tok_buf = []
      for token in old {
        match token {
          Invisible(widths) =>
            if widths.search(0) is Some(start) {
              let first = widths[:start].to_array()
              if first.length() > 0 {
                tok_buf.append(MbtToken::Invisible(first).to_text())
              }
              current_line.val.push((modified, tok_buf))
              tok_buf = []
              full.push(current_line.val)
              current_line.val = []
              let segments = widths[start:].split(0)
              match segments {
                [] => return
                [.. segments, last] => {
                  for segment in segments {
                    if !(segment is []) {
                      full.push([
                        (
                          modified,
                          MbtToken::Invisible(segment.to_array()).to_text(),
                        ),
                      ])
                    } else {
                      full.push([])
                    }
                  }
                  // processing last
                  current_line.val.push(
                    (modified, MbtToken::Invisible(last.to_array()).to_text()),
                  )
                }
              }
            } else {
              tok_buf.append(token.to_text())
            }
          _ => tok_buf.append(token.to_text())
        }
      } else {
        if tok_buf.length() > 0 {
          current_line.val.push((modified, tok_buf))
        }
      }
    }
  }

  for edit in matching_block {
    match edit {
      Delete(old~) => process_edits(old, true, current_line_left, left)
      Insert(new~) => process_edits(new, true, current_line_right, right)
      Equal(old~, new~) => {
        process_edits(old, false, current_line_left, left)
        process_edits(new, false, current_line_right, right)
      }
    }
  } else {
    if current_line_left.val.length() > 0 {
      left.push(current_line_left.val)
    }
    if current_line_right.val.length() > 0 {
      right.push(current_line_right.val)
    }
  }
  return (left, right)
}

///|
fn soft_wrap(
  lines : Array[Array[(Bool, Array[Char])]],
) -> Array[(Bool, Array[(Bool, ArrayView[Char])])] {
  let result = []
  for line in lines {
    let mut current_visual_line : Array[(Bool, ArrayView[Char])] = []
    let mut current_width = 0
    let mut first = true
    for edit in line {
      let (is_modification, text) = edit
      if current_width + text.length() >= @config.max_line_width.val {
        let cut = @config.max_line_width.val - current_width
        current_visual_line.push((is_modification, text[:cut]))
        result.push((first, current_visual_line))
        current_visual_line = []
        current_width = 0
        if first {
          first = false
        }
        // process remaining part
        // two case:
        // - remaining part still longer than max_line_width
        // - small enough to fit in one line
        let mut rest = text[cut:]
        while rest.length() > @config.max_line_width.val {
          result.push(
            (first, [(is_modification, rest[:@config.max_line_width.val])]),
          )
          rest = rest[@config.max_line_width.val:]
        } else {
          if rest.length() > 0 {
            current_visual_line.push((is_modification, rest))
            current_width += rest.length()
          }
        }
      } else {
        current_visual_line.push((is_modification, text[:]))
        current_width += text.length()
      }
    } else {
      if current_visual_line.length() > 0 {
        result.push((first, current_visual_line))
      }
    }
  } else {
    return result
  }
}

///|
test "soft wrap" {
  let lines = [
    [
      (false, ['a', 'b', 'c', 'd', 'e']),
      (true, ['f', 'g', 'h', 'i', 'j', 'k', 'l', 'm']),
    ],
    [(true, ['1', '2', '3', '4', '5'])],
  ]
  @config.max_line_width.val = 5
  let wrapped = soft_wrap(lines)
  @json.inspect(wrapped, content=[
    [true, [[false, ["a", "b", "c", "d", "e"]]]],
    [false, [[true, ["f", "g", "h", "i", "j"]]]],
    [false, [[true, ["k", "l", "m"]]]],
    [true, [[true, ["1", "2", "3", "4", "5"]]]],
  ])
  @config.max_line_width.val = 4
  let wrapped = soft_wrap(lines)
  @json.inspect(wrapped, content=[
    [true, [[false, ["a", "b", "c", "d"]]]],
    [false, [[false, ["e"]], [true, ["f", "g", "h"]]]],
    [false, [[true, ["i", "j", "k", "l"]]]],
    [false, [[true, ["m"]]]],
    [true, [[true, ["1", "2", "3", "4"]]]],
    [false, [[true, ["5"]]]],
  ])
}

///|
fn ArrayView::split(
  self : ArrayView[Int],
  delimiter : Int,
) -> Array[ArrayView[Int]] {
  let result = []
  let mut prev = 0
  for i in 0..<self.length() {
    if self[i] == delimiter {
      result.push(self[prev:i])
      prev = i + 1
    }
  }
  result.push(self[prev:self.length()])
  return result
}

///|
test "split arrayview" {
  let widths = [0, 0, 4][:]
  @json.inspect(widths.split(0), content=[[], [], [4]])
  @json.inspect([][:].split(0), content=[[]])
  let widths = [0, 0][:]
  @json.inspect(widths.split(0), content=[[], [], []])
}

///|
let global_line_buffer : StringBuilder = StringBuilder::new()

///|
fn combine_two_line(
  left_line~ : Array[(Bool, ArrayView[Char])],
  right_line~ : Array[(Bool, ArrayView[Char])],
) -> String {
  global_line_buffer.reset()
  if left_line.is_empty() {
    for _ in 0..<@config.max_line_width.val {
      global_line_buffer.write_char(' ')
    }
  } else {
    let mut width = 0
    for edit in left_line {
      let (is_modification, text) = edit
      width += text.length()
      if is_modification {
        global_line_buffer.write_string(
          @chalk.chalk().color(Red).render(String::from_array(text)),
        )
      } else {
        global_line_buffer.write_iter(text.iter())
      }
    }
    if width != @config.max_line_width.val {
      for _ in 0..<(@config.max_line_width.val - width) {
        global_line_buffer.write_char(' ')
      }
    }
  }
  global_line_buffer.write_string(" | ")
  if !right_line.is_empty() {
    for edit in right_line {
      let (is_modification, text) = edit
      if is_modification {
        global_line_buffer.write_string(
          @chalk.chalk().color(Green).render(String::from_array(text)),
        )
      } else {
        global_line_buffer.write_iter(text.iter())
      }
    }
  }
  return global_line_buffer.to_string()
}

///|
fn rendering_matching_block(
  matching_block : Array[Edit[Array[MbtToken]]],
) -> Unit {
  let (left_lines, right_lines) = split_matching_block(matching_block)
  let left_lines = soft_wrap(left_lines)
  let right_lines = soft_wrap(right_lines)
  let max_line = left_lines.length().max(right_lines.length())
  for i in 0..<max_line {
    let left_line = if i < left_lines.length() { left_lines[i].1 } else { [] }
    let right_line = if i < right_lines.length() {
      right_lines[i].1
    } else {
      []
    }
    let rendered_line = combine_two_line(left_line~, right_line~)
    println(rendered_line)
  }
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
    rendering_matching_block(matching_block)
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
  let spec : Array[(String, String, @ArgParser.Spec, String)] = []
  let filenames = []
  let usage =
    #| usage: 
    #|   tokendiff <old file> <new file>
  @ArgParser.parse(spec, filename => filenames.push(filename), usage, args)
  if filenames is [old, new] {
    try {
      let old = @fs.read_file_to_string(old)
      let new = @fs.read_file_to_string(new)
      do_all(old~, new~)
    } catch {
      e => {
        println("Error: " + e.to_string())
        panic()
      }
    }
  } else {
    println("unexpected filenames: \{filenames}")
    println(usage)
    panic()
  }
}
