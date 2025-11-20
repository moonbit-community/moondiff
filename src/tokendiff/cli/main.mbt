///|
using @edit {type Edit}

///|
using @mbttoken {type MbtToken}

///|
fn pairing_blocks(
  old~ : String,
  new~ : String,
) -> Array[@block.EditBlock] raise Error {
  let old = @block.create_blocks(old)
  let new = @block.create_blocks(new)
  @block.pairing_blocks_by_uuid(old~, new~)
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
              token.emit_text_to(tok_buf)
            }
          _ => token.emit_text_to(tok_buf)
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
      if current_width + text.length() >= max_line_width.val {
        let cut = max_line_width.val - current_width
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
        while rest.length() > max_line_width.val {
          result.push((first, [(is_modification, rest[:max_line_width.val])]))
          rest = rest[max_line_width.val:]
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
  max_line_width.val = 5
  let wrapped = soft_wrap(lines)
  @json.inspect(wrapped, content=[
    [true, [[false, ["a", "b", "c", "d", "e"]]]],
    [false, [[true, ["f", "g", "h", "i", "j"]]]],
    [false, [[true, ["k", "l", "m"]]]],
    [true, [[true, ["1", "2", "3", "4", "5"]]]],
  ])
  max_line_width.val = 4
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
    for _ in 0..<max_line_width.val {
      global_line_buffer.write_char(' ')
    }
  } else {
    let mut width = 0
    for edit in left_line {
      let (is_modification, text) = edit
      width += text.length()
      if is_modification {
        global_line_buffer.write_string(
          @chalk.chalk()
          .color(Red)
          .modifier(Bold)
          .render(String::from_array(text)),
        )
      } else {
        global_line_buffer.write_iter(text.iter())
      }
    }
    if width != max_line_width.val {
      for _ in 0..<(max_line_width.val - width) {
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
          @chalk.chalk()
          .color(Green)
          .modifier(Bold)
          .render(String::from_array(text)),
        )
      } else {
        global_line_buffer.write_iter(text.iter())
      }
    }
  }
  return global_line_buffer.to_string()
}

///|
fn rendering_matching_block_side_by_side(
  matching_block : Array[Edit[Array[MbtToken]]],
) -> String {
  let buf = StringBuilder::new()
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
    buf.write_string(rendered_line)
    buf.write_char('\n')
  }
  return buf.to_string()
}

///|
using @line_group {type REdit}

///|
fn rendering_matching_block(matching_block_line_group : Array[REdit]) -> String {
  let buf = StringBuilder::new()
  let red = @chalk.chalk().color(Red).modifier(Bold)
  let green = @chalk.chalk().color(Green).modifier(Bold)
  // let blue = @chalk.chalk().color(Blue).modifier(Bold)
  let gray = @chalk.chalk().color(BlackBright)
  for line_group in matching_block_line_group {
    match line_group {
      Replace(old~, new~) => {
        let old = old.join("\n")
        let new = new.join("\n")
        let old_toks = @mbttoken.MbtToken::from_str(old)
        let new_toks = @mbttoken.MbtToken::from_str(new)
        let edits = @diff_with_opt.diff_with_opt(old=old_toks, new=new_toks)
        if edits is [Equal(..)] {
          buf.write_string(new)
          buf.write_char('\n')
          continue
        }
        let (old_lines, new_lines) = split_matching_block(edits)
        for old_line in old_lines {
          if old_line.is_empty() {
            continue
          }
          buf.write_string(red.render("-|") + "  ")
          for edit in old_line {
            let (is_modification, text) = edit
            if is_modification {
              buf.write_string(red.render(String::from_array(text)))
            } else {
              buf.write_iter(text.iter())
            }
          }
          buf.write_char('\n')
        }
        for new_line in new_lines {
          if new_line.is_empty() {
            continue
          }
          buf.write_string(green.render("+|") + "  ")
          for edit in new_line {
            let (is_modification, text) = edit
            if is_modification {
              buf.write_string(green.render(String::from_array(text)))
            } else {
              buf.write_iter(text.iter())
            }
          }
          buf.write_char('\n')
        }
      }
      Normal(edit) =>
        match edit {
          Delete(old~) =>
            for line in old {
              buf.write_string(red.render("-|") + "  ")
              buf.write_stringview(red.render(line))
              buf.write_char('\n')
            }
          Insert(new~) =>
            for line in new {
              buf.write_string(green.render("+|") + "  ")
              buf.write_stringview(green.render(line))
              buf.write_char('\n')
            }
          Equal(old~, ..) =>
            for line in old {
              buf.write_string(gray.render("=|") + "  ")
              buf.write_stringview(gray.render(line))
              buf.write_char('\n')
            }
        }
    }
  }
  return buf.to_string()
}

///|
fn do_all(old_filename~ : String, new_filename~ : String) -> Unit raise {
  let old = @fs.read_file_to_string(old_filename)
  let new = @fs.read_file_to_string(new_filename)
  if !(old_filename.has_suffix(".mbt") && new_filename.has_suffix(".mbt")) {
    // fallback to line diff
    let bold = @chalk.chalk().modifier(Bold)
    println(bold.render("--- \{old_filename}"))
    println(bold.render("+++ \{new_filename}"))
    let diff = fallback_to_linediff(old~, new~)
    println(diff)
    return
  }
  let blocks = pairing_blocks(old~, new~)
  for blk in blocks {
    match blk {
      Delete(blk) =>
        println(
          @chalk.chalk()
          .color(Red)
          .render(
            "--- \{old_filename}: line \{blk.start_line}, deleted block \{blk.uuid} \n\n",
          ),
        )
      Insert(blk) =>
        println(
          @chalk.chalk()
          .color(Green)
          .render(
            "+++ \{new_filename}: line \{blk.start_line} inserted block \{blk.uuid} \n\n",
          ),
        )
      Replace(old~, new~) => {
        println("--- \{old_filename}: line \{old.start_line}")
        println("+++ \{new_filename}: line \{new.start_line}")
        let edits = if display_side_by_side.val {
          let old = @mbttoken.MbtToken::from_str(old.contents)
          let new = @mbttoken.MbtToken::from_str(new.contents)
          let edits = @diff_with_opt.diff_with_opt(old~, new~)
          rendering_matching_block_side_by_side(edits)
        } else {
          let edits = @line_group.line_group(old.contents, new.contents)
          rendering_matching_block(edits)
        }
        println(edits)
      }
    }
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  let spec : Array[(String, String, @ArgParser.Spec, String)] = [
    (
      "--display-side-by-side",
      "-ss",
      @ArgParser.Spec::Set(display_side_by_side),
      "Display diff side by side",
    ),
  ]
  let filenames = []
  let usage =
    #| usage: 
    #|   tokendiff <old file> <new file>
  @ArgParser.parse(
    spec,
    filename => filenames.push(filename),
    usage,
    args[1:].to_array(),
  )
  if filenames is [old_filename, new_filename] {
    do_all(old_filename~, new_filename~) catch {
      e => {
        println("Error: " + e.to_string())
        panic()
      }
    }
  } else if filenames is [] {
    // peaceful exit
    println("No input files provided.")
  } else {
    println("unexpected filenames: \{filenames}")
    println(usage)
    panic()
  }
}
