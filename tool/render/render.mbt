///|UUID(4c963221-4eea-4a97-95c2-09ed50ace4a9)
// Changed highlight ranges grouped by one-based line numbers relative to the
// text supplied to `render_line_diff`.
type HighlightMap = @hashmap.HashMap[Int, Array[(Int, Int)]]

///|UUID(58e0f8c9-2d25-44d5-b23b-f729f3341d84)
// Rendering controls shared by structural and fallback line diffs.
pub struct RenderOptions {
  context_lines : Int
  use_color : Bool
}

///|UUID(777a738b-08e7-4d99-8186-fde9524531ab)
// Piediff requires a non-negative grouping radius. Clamp at this public
// boundary so line and structural rendering share the same safe behavior.
pub fn RenderOptions::new(
  context_lines? : Int = 3,
  use_color? : Bool = false,
) -> Self {
  let context_lines = if context_lines < 0 { 0 } else { context_lines }
  { context_lines, use_color }
}

///|UUID(8b903a0c-90d4-4242-b885-8d74d5f6d260)
priv enum LineStyle {
  Context
  Deleted
  Added
}

///|UUID(32757abf-5f53-4a4d-bb1a-3df50a424d47)
// Split on LF and CRLF. This intentionally returns a non-empty array and keeps
// a trailing empty line, unlike APIs that treat `foo\n` as one line.
pub fn split_lines(source : String) -> Array[String] {
  @source_text.split_lines(source)
}

///|UUID(7b86a3ce-71eb-4062-b338-914509d4793a)
fn repeat_char(ch : Char, width : Int) -> String {
  let buf = StringBuilder(size_hint=width)
  for _ in 0..<width {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|UUID(4a548ca3-bd2d-4a39-9c5e-77c5501d85f3)
fn line_no_color(style : LineStyle) -> @chalk.Colors {
  match style {
    Context => BlackBright
    Deleted => Red
    Added => Green
  }
}

///|UUID(1c1b85e4-6d10-43c1-a7d6-e6b5268be2c3)
// Display dots when a line has no counterpart on that side, matching the
// visual convention used by difftastic's side-by-side renderer.
fn display_line_no(
  line_no : Int?,
  width : Int,
  line_base : Int,
  style : LineStyle,
  use_color : Bool,
) -> String {
  if line_no is Some(line_no) {
    let value = (line_no + line_base).to_string()
    let padding = repeat_char(' ', @cmp.maximum(width - value.length(), 0))
    if use_color {
      padding + @chalk.chalk().color(line_no_color(style)).render(value)
    } else {
      padding + value
    }
  } else {
    let dots = repeat_char('.', width)
    if use_color {
      @chalk.chalk().color(BlackBright).render(dots)
    } else {
      dots
    }
  }
}

///|UUID(6a7523d6-13fe-4ad1-9d78-e8e8d32b2f45)
fn line_prefix(
  _marker : String,
  old_line_no : Int?,
  old_width : Int,
  old_line_base : Int,
  new_line_no : Int?,
  new_width : Int,
  new_line_base : Int,
  style : LineStyle,
  use_color : Bool,
) -> String {
  "\{display_line_no(old_line_no, old_width, old_line_base, style, use_color)} \{display_line_no(new_line_no, new_width, new_line_base, style, use_color)}"
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

///|UUID(fb6c161d-a7a0-4606-8cd8-1e401ce07176)
fn style_file_header(text : String, use_color : Bool) -> String {
  if use_color {
    @chalk.chalk().color(Blue).render(text)
  } else {
    text
  }
}

///|UUID(06f17b4e-fb70-42ea-880f-a1af1661af4e)
pub fn render_file_headers(
  old_label : String,
  new_label : String,
  use_color : Bool,
) -> String {
  style_file_header("--- \{old_label}", use_color) +
  "\n" +
  style_file_header("+++ \{new_label}", use_color) +
  "\n"
}

///|UUID(3209ce96-bf1f-4476-aaab-bb49814c52f5)
// Apply intra-line changed spans. Span positions are relative to parser/source
// offsets, so normalization happens before slicing the visible string.
fn render_line_body(
  line : String,
  ranges : Array[(Int, Int)]?,
  style : LineStyle,
  use_color : Bool,
  plain_context_line : Bool,
) -> String {
  if !use_color {
    return line
  }
  let ranges = if ranges is Some(ranges) {
    ranges
  } else if plain_context_line && style is Context {
    return line
  } else {
    return style_text(line, style, true)
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
    // `SingleLineSpan` currently mixes 1-based parser columns with
    // synthetic 0-based full-line spans. Normalize to 0-based
    // half-open ranges here.
    let start = if start_col == 0 { 0 } else { @cmp.maximum(start_col - 1, 0) }
    let end = @cmp.minimum(
      if start_col == 0 {
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
    if plain_context_line && style is Context {
      return line
    } else {
      return style_text(line, style, true)
    }
  }

  let buf = StringBuilder(size_hint=line.length())
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
      buf.write_string(style_text(segment, Context, true))
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
  plain_context_line : Bool,
) -> String {
  line_prefix(
    marker, old_line_no, old_width, old_line_base, new_line_no, new_width, new_line_base,
    style, use_color,
  ) +
  " " +
  render_line_body(line, ranges, style, use_color, plain_context_line)
}

///|
fn document_line_has_change(line : @model.DiffLine) -> Bool {
  line.segments.any(segment => segment.kind is Changed)
}

///|
fn render_document_line_body(
  line : @model.DiffLine,
  changed_style : LineStyle,
  use_color : Bool,
) -> String {
  if !use_color {
    return line.text()
  }
  let buf = StringBuilder()
  for segment in line.segments {
    buf.write_string(
      style_text(
        segment.text,
        if segment.kind is Changed {
          changed_style
        } else {
          Context
        },
        true,
      ),
    )
  }
  buf.to_string()
}

///|
fn append_document_change_line(
  buf : StringBuilder,
  line : @model.DiffLine,
  old_side : Bool,
  old_width : Int,
  new_width : Int,
  use_color : Bool,
) -> Unit {
  let changed_style = if old_side { Deleted } else { Added }
  let number_style = if line.segments.is_empty() ||
    document_line_has_change(line) {
    changed_style
  } else {
    Context
  }
  buf.write_string(
    line_prefix(
      if old_side {
        "-"
      } else {
        "+"
      },
      if old_side {
        Some(line.index)
      } else {
        None
      },
      old_width,
      1,
      if old_side {
        None
      } else {
        Some(line.index)
      },
      new_width,
      1,
      number_style,
      use_color,
    ) +
    " " +
    render_document_line_body(line, changed_style, use_color),
  )
  buf.write_char('\n')
}

///|
fn append_document_context_line(
  buf : StringBuilder,
  old_index : Int?,
  new_index : Int?,
  text : String,
  old_width : Int,
  new_width : Int,
  use_color : Bool,
) -> Unit {
  buf.write_string(
    render_hunk_line(
      " ",
      old_index,
      old_width,
      1,
      new_index,
      new_width,
      1,
      text,
      None,
      Context,
      use_color,
      true,
    ),
  )
  buf.write_char('\n')
}

///|
fn append_document_change_row(
  buf : StringBuilder,
  row : @model.DiffRow,
  old_width : Int,
  new_width : Int,
  use_color : Bool,
) -> Unit {
  match row {
    Paired(old_line, new_line) => {
      append_document_change_line(
        buf, old_line, true, old_width, new_width, use_color,
      )
      append_document_change_line(
        buf, new_line, false, old_width, new_width, use_color,
      )
    }
    OldOnly(line) =>
      append_document_change_line(
        buf, line, true, old_width, new_width, use_color,
      )
    NewOnly(line) =>
      append_document_change_line(
        buf, line, false, old_width, new_width, use_color,
      )
  }
}

///|
fn append_document_ignored_row(
  buf : StringBuilder,
  row : @model.DiffRow,
  old_width : Int,
  new_width : Int,
  use_color : Bool,
) -> Unit {
  match row {
    Paired(old_line, new_line) =>
      if old_line.text() == new_line.text() {
        append_document_context_line(
          buf,
          Some(old_line.index),
          Some(new_line.index),
          old_line.text(),
          old_width,
          new_width,
          use_color,
        )
      } else {
        append_document_context_line(
          buf,
          Some(old_line.index),
          None,
          old_line.text(),
          old_width,
          new_width,
          use_color,
        )
        append_document_context_line(
          buf,
          None,
          Some(new_line.index),
          new_line.text(),
          old_width,
          new_width,
          use_color,
        )
      }
    OldOnly(line) =>
      append_document_context_line(
        buf,
        Some(line.index),
        None,
        line.text(),
        old_width,
        new_width,
        use_color,
      )
    NewOnly(line) =>
      append_document_context_line(
        buf,
        None,
        Some(line.index),
        line.text(),
        old_width,
        new_width,
        use_color,
      )
  }
}

///|
fn update_document_max_line(max_line : Ref[Int], index : Int) -> Unit {
  max_line.val = @cmp.maximum(max_line.val, index + 1)
}

///|
fn document_line_widths(document : @model.DiffDocument) -> (Int, Int) {
  let old_max = Ref(1)
  let new_max = Ref(1)
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) =>
          for line in lines {
            update_document_max_line(old_max, line.old_index)
            update_document_max_line(new_max, line.new_index)
          }
        ChangeBlock(rows) | IgnoredBlock(rows) =>
          for row in rows {
            match row {
              Paired(old_line, new_line) => {
                update_document_max_line(old_max, old_line.index)
                update_document_max_line(new_max, new_line.index)
              }
              OldOnly(line) => update_document_max_line(old_max, line.index)
              NewOnly(line) => update_document_max_line(new_max, line.index)
            }
          }
      }
    }
  }
  (old_max.val.to_string().length(), new_max.val.to_string().length())
}

///|
/// Render a calculated diff document with the terminal renderer's file
/// headers, two line-number columns, and optional ANSI highlighting. An empty
/// document renders only its file headers so the caller can choose the most
/// accurate empty-state message.
fn render_diff_document_impl(
  old_label : String,
  new_label : String,
  document : @model.DiffDocument,
  options : RenderOptions,
  old_max_line : Int?,
  new_max_line : Int?,
) -> String {
  let (document_old_width, document_new_width) = document_line_widths(document)
  let old_width = old_max_line
    .map(line => @cmp.maximum(line, 1).to_string().length())
    .map(width => @cmp.maximum(width, document_old_width))
    .unwrap_or(document_old_width)
  let new_width = new_max_line
    .map(line => @cmp.maximum(line, 1).to_string().length())
    .map(width => @cmp.maximum(width, document_new_width))
    .unwrap_or(document_new_width)
  let buf = StringBuilder()
  buf.write_string(render_file_headers(old_label, new_label, options.use_color))
  for hunk in document.hunks {
    buf.write_string(
      @common.hunk_header(
        hunk.old_start,
        hunk.old_len,
        hunk.new_start,
        hunk.new_len,
      ),
    )
    buf.write_char('\n')
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) =>
          for line in lines {
            append_document_context_line(
              buf,
              Some(line.old_index),
              Some(line.new_index),
              line.text,
              old_width,
              new_width,
              options.use_color,
            )
          }
        ChangeBlock(rows) =>
          for row in rows {
            append_document_change_row(
              buf,
              row,
              old_width,
              new_width,
              options.use_color,
            )
          }
        IgnoredBlock(rows) =>
          for row in rows {
            append_document_ignored_row(
              buf,
              row,
              old_width,
              new_width,
              options.use_color,
            )
          }
      }
    }
  }
  buf.to_string()
}

///|
/// Render a calculated diff document with widths inferred from its rows.
pub fn render_diff_document(
  old_label : String,
  new_label : String,
  document : @model.DiffDocument,
  options : RenderOptions,
) -> String {
  render_diff_document_impl(old_label, new_label, document, options, None, None)
}

///|
/// Render a document while reserving line-number widths for complete source
/// sections. This preserves the historical terminal layout when a calculated
/// hunk covers only part of a top-level declaration.
pub fn render_diff_document_with_max_lines(
  old_label : String,
  new_label : String,
  document : @model.DiffDocument,
  options : RenderOptions,
  old_max_line : Int,
  new_max_line : Int,
) -> String {
  render_diff_document_impl(
    old_label,
    new_label,
    document,
    options,
    Some(old_max_line),
    Some(new_max_line),
  )
}

///|UUID(15f32630-dc4b-4303-aa24-c9bd98ee0b12)
fn max_display_line(line_base : Int, line_count : Int) -> Int {
  if line_count == 0 {
    line_base
  } else {
    line_base + line_count - 1
  }
}

///|UUID(e282663c-5f0b-4f1d-8b46-5463657976a4)
// Plain line-oriented diff retained for non-MoonBit inputs and callers that
// only have text-level highlights. When highlight maps are provided here,
// their keys are one-based line numbers in the supplied text.
const CORE_LINE_DIFF_CUTOFF : Int = 4_096

///|
pub fn render_line_diff(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  old_highlights : HighlightMap?,
  new_highlights : HighlightMap?,
  options : RenderOptions,
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
  let diff = @diff.Diff(
    old=old_lines[:],
    new=new_lines[:],
    cutoff=CORE_LINE_DIFF_CUTOFF,
  )
  let hunks = diff.group(context=options.context_lines)

  let buf = StringBuilder()
  buf.write_string(render_file_headers(old_label, new_label, options.use_color))
  if hunks.is_empty() {
    buf.write_string("No changes.\n")
    return buf.to_string()
  }

  for hunk in hunks {
    buf.write_string(hunk.header())
    buf.write_char('\n')
    for edit in hunk.edits() {
      match edit {
        @diff.Edit::Delete(old_index~, old_len~, ..) =>
          for i in 0..<old_len {
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
                false,
              ),
            )
            buf.write_char('\n')
          }
        @diff.Edit::Insert(new_index~, new_len~, ..) =>
          for i in 0..<new_len {
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
                false,
              ),
            )
            buf.write_char('\n')
          }
        @diff.Edit::Equal(old_index~, new_index~, len~) =>
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
