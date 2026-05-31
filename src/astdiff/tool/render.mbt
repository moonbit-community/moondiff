///|UUID(4c963221-4eea-4a97-95c2-09ed50ace4a9)
type HighlightMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|UUID(8b903a0c-90d4-4242-b885-8d74d5f6d260)
priv enum LineStyle {
  Context
  Deleted
  Added
}

///|UUID(32757abf-5f53-4a4d-bb1a-3df50a424d47)
fn split_lines(source : String) -> Array[String] {
  let lines = Array::new()
  for line in source.split("\n") {
    let chars = line.to_array()
    if chars.last() is Some('\r') {
      lines.push(String::from_array(chars[:chars.length() - 1].to_owned()))
    } else {
      lines.push(line.to_owned())
    }
  } nobreak {
    lines
  }
}

///|UUID(534e9df8-b623-4a6b-a906-d4e565976377)
fn add_changed_span(
  highlights : HighlightMap,
  line : Int,
  start_col : Int,
  end_col : Int,
) -> Unit {
  if end_col <= start_col {
    return
  }
  match highlights.get(line) {
    Some(ranges) => ranges.push((start_col, end_col))
    None => highlights.set(line, [(start_col, end_col)])
  }
}

///|UUID(e85e59c2-20e3-4407-ae4d-acba47947ac7)
fn collect_novel_ranges(mps : ArrayView[MatchedPos]) -> HighlightMap {
  let highlights = @hashmap.HashMap([])
  for mp in mps {
    if !mp.kind.is_novel() {
      continue
    }
    let line = line_index(mp.pos)
    if line < 0 {
      continue
    }
    add_changed_span(highlights, line, mp.pos.start_col, mp.pos.end_col)
  } nobreak {
    highlights
  }
}

///|UUID(d4848c4e-44ca-415a-8ce8-39306301dd72)
fn pad_left(value : String, width : Int) -> String {
  if value.length() >= width {
    return value
  }
  let buf = StringBuilder::new(size_hint=width)
  for _ in 0..<(width - value.length()) {
    buf.write_char(' ')
  }
  buf.write_string(value)
  buf.to_string()
}

///|UUID(1c1b85e4-6d10-43c1-a7d6-e6b5268be2c3)
fn display_line_no(line_no : Int?, width : Int, line_base : Int) -> String {
  match line_no {
    Some(line_no) => pad_left((line_no + line_base).to_string(), width)
    None => pad_left("", width)
  }
}

///|UUID(6a7523d6-13fe-4ad1-9d78-e8e8d32b2f45)
fn line_prefix(
  marker : String,
  old_line_no : Int?,
  old_width : Int,
  old_line_base : Int,
  new_line_no : Int?,
  new_width : Int,
  new_line_base : Int,
) -> String {
  "\{marker} \{display_line_no(old_line_no, old_width, old_line_base)} \{display_line_no(new_line_no, new_width, new_line_base)} | "
}

///|UUID(fc528109-6fac-4326-b0fc-a00841bea702)
fn style_prefix(prefix : String, style : LineStyle, use_color : Bool) -> String {
  if !use_color {
    return prefix
  }
  match style {
    Context => @chalk.chalk().color(BlackBright).render(prefix)
    Deleted => @chalk.chalk().color(Red).modifier(Bold).render(prefix)
    Added => @chalk.chalk().color(Green).modifier(Bold).render(prefix)
  }
}

///|UUID(665cb8b1-546a-4c3f-af21-5f80889a1ee3)
fn style_text(text : String, style : LineStyle, use_color : Bool) -> String {
  if !use_color {
    return text
  }
  match style {
    Context => @chalk.chalk().color(BlackBright).render(text)
    Deleted => @chalk.chalk().color(Red).modifier(Bold).render(text)
    Added => @chalk.chalk().color(Green).modifier(Bold).render(text)
  }
}

///|UUID(3209ce96-bf1f-4476-aaab-bb49814c52f5)
fn render_line_body(
  line : String,
  ranges : Array[(Int, Int)]?,
  style : LineStyle,
  use_color : Bool,
  full_line_fallback : Bool,
) -> String {
  if !use_color {
    if full_line_fallback {
      return style_text(line, style, use_color)
    } else {
      return line
    }
  }
  let ranges = match ranges {
    Some(ranges) => ranges
    None =>
      if full_line_fallback {
        return style_text(line, style, use_color)
      } else {
        return line
      }
  }
  let chars = line.to_array()
  if chars.is_empty() {
    return ""
  }
  let mask = Array::new(capacity=chars.length())
  for _ in 0..<chars.length() {
    mask.push(false)
  }
  let mut has_highlight = false
  for range in ranges {
    let (start_col, end_col) = range
    let start = @cmp.maximum(start_col - 1, 0)
    // `SingleLineSpan` currently mixes 1-based parser columns with
    // synthetic 0-based full-line spans. Normalize to 0-based
    // half-open ranges here.
    let end = @cmp.minimum(
      if start_col == 0 && end_col == chars.length() {
        end_col
      } else if start_col > 0 && end_col == chars.length() {
        end_col
      } else {
        end_col - 1
      },
      chars.length(),
    )
    for i in start..<end {
      mask[i] = true
      has_highlight = true
    }
  }
  if !has_highlight {
    if full_line_fallback {
      return style_text(line, style, use_color)
    } else {
      return line
    }
  }

  let buf = StringBuilder::new(size_hint=line.length())
  let mut start = 0
  while start < chars.length() {
    let highlighted = mask[start]
    let mut end = start + 1
    while end < chars.length() && mask[end] == highlighted {
      end += 1
    }
    let segment = String::from_array(chars[start:end].to_owned())
    if highlighted {
      buf.write_string(style_text(segment, style, true))
    } else {
      buf.write_string(segment)
    }
    start = end
  }
  buf.to_string()
}

///|UUID(adf51724-e0ec-4539-a73d-adbbd1903cf2)
fn render_hunk_line(
  marker : String,
  old_line_no : Int?,
  old_width : Int,
  old_line_base : Int,
  new_line_no : Int?,
  new_width : Int,
  new_line_base : Int,
  line : String,
  ranges : Array[(Int, Int)]?,
  style : LineStyle,
  use_color : Bool,
  full_line_fallback : Bool,
) -> String {
  style_prefix(
    line_prefix(
      marker, old_line_no, old_width, old_line_base, new_line_no, new_width, new_line_base,
    ),
    style,
    use_color,
  ) +
  render_line_body(line, ranges, style, use_color, full_line_fallback)
}

///|UUID(d0d1ad18-199b-4b66-b233-b6a36da07412)
fn range_text(start : Int, end_ : Int, line_base : Int) -> String {
  let mut beginning = start + line_base
  let len = end_ - start
  if len == 1 {
    beginning.to_string()
  } else {
    if len == 0 {
      beginning -= 1
    }
    "\{beginning},\{len}"
  }
}

///|UUID(44f0192c-760a-4982-a364-ebbfac834504)
fn piediff_old_range(edit : @piediff.Edit) -> (Int, Int) {
  match edit {
    @piediff.Edit::Insert(old_index~, ..) => (old_index, old_index)
    @piediff.Edit::Delete(old_index~, len~, ..) => (old_index, old_index + len)
    @piediff.Edit::Equal(old_index~, len~, ..) => (old_index, old_index + len)
  }
}

///|UUID(bfafc989-9115-4d84-93ba-f7e599e48f59)
fn piediff_new_range(edit : @piediff.Edit) -> (Int, Int) {
  match edit {
    @piediff.Edit::Insert(new_index~, len~, ..) => (new_index, new_index + len)
    @piediff.Edit::Delete(new_index~, ..) => (new_index, new_index)
    @piediff.Edit::Equal(new_index~, len~, ..) => (new_index, new_index + len)
  }
}

///|UUID(eb698c34-ec71-4ac9-91a6-35c6c6688d34)
fn render_piediff_hunk_header(edits : ArrayView[@piediff.Edit]) -> String {
  let (first_old_start, first_old_end) = piediff_old_range(edits[0])
  let (first_new_start, first_new_end) = piediff_new_range(edits[0])
  let mut old_end = first_old_end
  let mut new_end = first_new_end
  let mut found_old_end = false
  let mut found_new_end = false
  let mut i = edits.length()
  while i > 0 {
    i -= 1
    let edit = edits[i]
    let (edit_old_start, edit_old_end) = piediff_old_range(edit)
    let (edit_new_start, edit_new_end) = piediff_new_range(edit)
    if !found_old_end && edit_old_start != edit_old_end {
      old_end = edit_old_end
      found_old_end = true
    }
    if !found_new_end && edit_new_start != edit_new_end {
      new_end = edit_new_end
      found_new_end = true
    }
    if found_old_end && found_new_end {
      break
    }
  }
  "@@ -\{range_text(first_old_start, old_end, 1)} +\{range_text(first_new_start, new_end, 1)} @@"
}

///|UUID(8d2ad4b6-7974-44d6-871b-1ef554920ad2)
fn hunk_side_range(
  lines : ArrayView[(Int?, Int?)],
  use_old_side : Bool,
) -> (Int, Int) {
  let first = Ref(None)
  let last = Ref(None)
  let fallback = Ref(0)
  for pair in lines {
    let (old_line, new_line) = pair
    let selected = if use_old_side { old_line } else { new_line }
    let opposite = if use_old_side { new_line } else { old_line }
    if selected is Some(line) {
      if first.val is None {
        first.val = Some(line)
      }
      last.val = Some(line)
    } else if fallback.val == 0 && opposite is Some(line) {
      fallback.val = line
    }
  }
  match (first.val, last.val) {
    (Some(first), Some(last)) => (first, last + 1)
    _ => (fallback.val, fallback.val)
  }
}

///|UUID(0d6af434-a7db-4978-8293-a43d8240937e)
fn render_hunk_header(
  lines : ArrayView[(Int?, Int?)],
  old_line_base : Int,
  new_line_base : Int,
) -> String {
  let (old_start, old_end) = hunk_side_range(lines, true)
  let (new_start, new_end) = hunk_side_range(lines, false)
  "@@ -\{range_text(old_start, old_end, old_line_base)} +\{range_text(new_start, new_end, new_line_base)} @@"
}

///|UUID(15f32630-dc4b-4303-aa24-c9bd98ee0b12)
fn max_display_line(line_base : Int, line_count : Int) -> Int {
  if line_count == 0 {
    line_base
  } else {
    line_base + line_count - 1
  }
}

///|UUID(26becb16-0cfd-4d6f-9587-97054b5ddfbb)
fn render_ast_diff(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
  options : DiffOptions,
  old_line_base? : Int = 1,
  new_line_base? : Int = 1,
) -> String {
  let old_lines = split_lines(old_source)
  let new_lines = split_lines(new_source)
  let old_line_no_width = max_display_line(old_line_base, old_lines.length())
    .to_string()
    .length()
  let new_line_no_width = max_display_line(new_line_base, new_lines.length())
    .to_string()
    .length()
  let old_highlights = collect_novel_ranges(lhs_mps)
  let new_highlights = collect_novel_ranges(rhs_mps)
  let matched_lines = all_matched_lines_filled(
    lhs_mps, rhs_mps, old_lines, new_lines,
  )
  let hunks = merge_adjacent_hunks(
    matched_pos_to_hunks(lhs_mps, rhs_mps),
    matched_lines,
    options.context_lines,
  )

  let buf = StringBuilder::new()
  buf.write_string("--- \{old_label}\n")
  buf.write_string("+++ \{new_label}\n")
  if hunks.is_empty() {
    buf.write_string("No changes.\n")
    return buf.to_string()
  }

  for hunk in hunks {
    let render_context_lines = options.context_lines + 1
    let (start, end_) = contextual_index_range_for_hunk(
      hunk, matched_lines, render_context_lines,
    )
    let lines = matched_lines[start:end_]
    buf.write_string(render_hunk_header(lines, old_line_base, new_line_base))
    buf.write_char('\n')
    for pair in lines {
      match pair {
        (Some(old_line), Some(new_line)) => {
          let old_is_novel = hunk.novel_lhs.contains(old_line)
          let new_is_novel = hunk.novel_rhs.contains(new_line)
          if !old_is_novel &&
            !new_is_novel &&
            old_lines[old_line] == new_lines[new_line] {
            buf.write_string(
              render_hunk_line(
                " ",
                Some(old_line),
                old_line_no_width,
                old_line_base,
                Some(new_line),
                new_line_no_width,
                new_line_base,
                old_lines[old_line],
                None,
                Context,
                options.use_color,
                false,
              ),
            )
            buf.write_char('\n')
          } else {
            buf.write_string(
              render_hunk_line(
                if old_is_novel {
                  "-"
                } else {
                  " "
                },
                Some(old_line),
                old_line_no_width,
                old_line_base,
                None,
                new_line_no_width,
                new_line_base,
                old_lines[old_line],
                old_highlights.get(old_line),
                if old_is_novel {
                  Deleted
                } else {
                  Context
                },
                options.use_color,
                false,
              ),
            )
            buf.write_char('\n')
            buf.write_string(
              render_hunk_line(
                if new_is_novel {
                  "+"
                } else {
                  " "
                },
                None,
                old_line_no_width,
                old_line_base,
                Some(new_line),
                new_line_no_width,
                new_line_base,
                new_lines[new_line],
                new_highlights.get(new_line),
                if new_is_novel {
                  Added
                } else {
                  Context
                },
                options.use_color,
                false,
              ),
            )
            buf.write_char('\n')
          }
        }
        (Some(old_line), None) => {
          let is_novel = hunk.novel_lhs.contains(old_line)
          buf.write_string(
            render_hunk_line(
              if is_novel {
                "-"
              } else {
                " "
              },
              Some(old_line),
              old_line_no_width,
              old_line_base,
              None,
              new_line_no_width,
              new_line_base,
              old_lines[old_line],
              old_highlights.get(old_line),
              if is_novel {
                Deleted
              } else {
                Context
              },
              options.use_color,
              false,
            ),
          )
          buf.write_char('\n')
        }
        (None, Some(new_line)) => {
          let is_novel = hunk.novel_rhs.contains(new_line)
          buf.write_string(
            render_hunk_line(
              if is_novel {
                "+"
              } else {
                " "
              },
              None,
              old_line_no_width,
              old_line_base,
              Some(new_line),
              new_line_no_width,
              new_line_base,
              new_lines[new_line],
              new_highlights.get(new_line),
              if is_novel {
                Added
              } else {
                Context
              },
              options.use_color,
              false,
            ),
          )
          buf.write_char('\n')
        }
        (None, None) => ()
      }
    }
  }
  buf.to_string()
}

///|UUID(e282663c-5f0b-4f1d-8b46-5463657976a4)
fn render_line_diff(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  old_highlights : HighlightMap?,
  new_highlights : HighlightMap?,
  options : DiffOptions,
  old_line_base? : Int = 1,
  new_line_base? : Int = 1,
) -> String {
  let old_lines = split_lines(old_source)
  let new_lines = split_lines(new_source)
  let old_line_no_width = max_display_line(old_line_base, old_lines.length())
    .to_string()
    .length()
  let new_line_no_width = max_display_line(new_line_base, new_lines.length())
    .to_string()
    .length()
  let diff = @piediff.Diff(old=old_lines[:], new=new_lines[:])
  let hunks = diff.group(radius=options.context_lines)

  let buf = StringBuilder::new()
  buf.write_string("--- \{old_label}\n")
  buf.write_string("+++ \{new_label}\n")
  if hunks.is_empty() {
    buf.write_string("No changes.\n")
    return buf.to_string()
  }

  for hunk in hunks {
    buf.write_string(render_piediff_hunk_header(hunk.edits))
    buf.write_char('\n')
    for edit in hunk.edits {
      match edit {
        @piediff.Edit::Delete(old_index~, len~, ..) =>
          for i in 0..<len {
            let line_no = old_index + i
            let ranges = old_highlights.bind(map => map.get(line_no + 1))
            buf.write_string(
              render_hunk_line(
                "-",
                Some(line_no),
                old_line_no_width,
                old_line_base,
                None,
                new_line_no_width,
                new_line_base,
                old_lines[line_no],
                ranges,
                Deleted,
                options.use_color,
                true,
              ),
            )
            buf.write_char('\n')
          }
        @piediff.Edit::Insert(new_index~, len~, ..) =>
          for i in 0..<len {
            let line_no = new_index + i
            let ranges = new_highlights.bind(map => map.get(line_no + 1))
            buf.write_string(
              render_hunk_line(
                "+",
                None,
                old_line_no_width,
                old_line_base,
                Some(line_no),
                new_line_no_width,
                new_line_base,
                new_lines[line_no],
                ranges,
                Added,
                options.use_color,
                true,
              ),
            )
            buf.write_char('\n')
          }
        @piediff.Edit::Equal(old_index~, new_index~, len~) =>
          for i in 0..<len {
            let old_line_no = old_index + i
            let new_line_no = new_index + i
            buf.write_string(
              render_hunk_line(
                " ",
                Some(old_line_no),
                old_line_no_width,
                old_line_base,
                Some(new_line_no),
                new_line_no_width,
                new_line_base,
                old_lines[old_line_no],
                None,
                Context,
                options.use_color,
                true,
              ),
            )
            buf.write_char('\n')
          }
      }
    }
  }
  buf.to_string()
}
