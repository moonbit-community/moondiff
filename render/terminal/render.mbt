///|
priv enum LineStyle {
  Context
  Deleted
  Added
}

///|
fn repeat_char(ch : Char, width : Int) -> String {
  let buf = StringBuilder(size_hint=width)
  for _ in 0..<width {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
fn line_no_color(style : LineStyle) -> @chalk.Colors {
  match style {
    Context => BlackBright
    Deleted => Red
    Added => Green
  }
}

///|
fn display_line_no(
  line_index : Int?,
  width : Int,
  style : LineStyle,
  use_color : Bool,
) -> String {
  if line_index is Some(line_index) {
    let value = (line_index + 1).to_string()
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

///|
fn line_prefix(
  old_line_index : Int?,
  old_width : Int,
  new_line_index : Int?,
  new_width : Int,
  style : LineStyle,
  use_color : Bool,
) -> String {
  "\{display_line_no(old_line_index, old_width, style, use_color)} \{display_line_no(new_line_index, new_width, style, use_color)}"
}

///|
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

///|
fn style_file_header(text : String, use_color : Bool) -> String {
  if use_color {
    @chalk.chalk().color(Blue).render(text)
  } else {
    text
  }
}

///|
fn render_file_headers(
  old_label : String,
  new_label : String,
  use_color : Bool,
) -> String {
  style_file_header("--- \{old_label}", use_color) +
  "\n" +
  style_file_header("+++ \{new_label}", use_color) +
  "\n"
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
        Some(line.index)
      } else {
        None
      },
      old_width,
      if old_side {
        None
      } else {
        Some(line.index)
      },
      new_width,
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
    line_prefix(old_index, old_width, new_index, new_width, Context, use_color) +
    " " +
    text,
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
fn document_line_widths(document : @model.HunkDocument) -> (Int, Int) {
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
fn hinted_width(hint : Int?, document_width : Int) -> Int {
  hint
  .map(line => @cmp.maximum(line, 1).to_string().length())
  .map(width => @cmp.maximum(width, document_width))
  .unwrap_or(document_width)
}

///|
/// Render one already calculated fragment `HunkDocument` with file headers,
/// two line-number columns, and optional ANSI highlighting. The renderer does
/// not flatten a high-level semantic document, calculate hunks, apply context,
/// normalize source text, or choose empty and fallback messages. An empty
/// document therefore renders only its headers. `hunk_context`, when nonempty,
/// is appended to every hunk heading in the fragment.
pub fn render_document(
  old_label : String,
  new_label : String,
  document : @model.HunkDocument,
  options? : RenderOptions = Default::default(),
  hunk_context? : String = "",
) -> String {
  let (document_old_width, document_new_width) = document_line_widths(document)
  let old_width = hinted_width(options.old_max_line, document_old_width)
  let new_width = hinted_width(options.new_max_line, document_new_width)
  let buf = StringBuilder()
  buf.write_string(render_file_headers(old_label, new_label, options.use_color))
  for hunk in document.hunks {
    buf.write_string(
      @render.hunk_header(
        hunk.old_start,
        hunk.old_len,
        hunk.new_start,
        hunk.new_len,
      ),
    )
    if !hunk_context.is_empty() {
      buf.write_char(' ')
      buf.write_string(hunk_context)
    }
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
