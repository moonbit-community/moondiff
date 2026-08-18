///|
/// A short annotation rendered immediately below a diff hunk header.
pub(all) struct HunkNote {
  title : String
  body : String
} derive(Eq)

///|
fn esc(text : String) -> String {
  let buf = StringBuilder::new()
  for char in text {
    match char {
      '&' => buf <+ "&amp;"
      '<' => buf <+ "&lt;"
      '>' => buf <+ "&gt;"
      _ => buf.write_char(char)
    }
  }
  buf.to_string()
}

///|
fn line_html(line : @tokdiff.DiffLine, changed_class : String) -> String {
  let buf = StringBuilder::new()
  for segment in line.segments {
    match segment.kind {
      Unchanged => buf <+ "\{esc(segment.text)}"
      Changed => buf <+ "<b class=\"\{changed_class}\">\{esc(segment.text)}</b>"
      Ignored =>
        buf <+ "<span class=\"ignored-context\">\{esc(segment.text)}</span>"
    }
  }
  buf.to_string()
}

///|
fn line_is_ignored(line : @tokdiff.DiffLine) -> Bool {
  !line.segments.is_empty() &&
  line.segments.all(segment => segment.kind is Ignored)
}

///|
fn line_number_text(number : Int?) -> String {
  if number is Some(value) {
    value.to_string()
  } else {
    ""
  }
}

///|
fn hunk_note_at(notes : ArrayView[HunkNote?], hunk_index : Int) -> HunkNote? {
  if notes.get(hunk_index) is Some(note) {
    note
  } else {
    None
  }
}

///|
fn table_hunk_note(buf : StringBuilder, note : HunkNote, columns : Int) -> Unit {
  buf <+
    "<tr><td class=\"hunk-note\" colspan=\"\{columns}\"><b class=\"hunk-note-title\">\{esc(note.title)}</b>: \{esc(note.body)}</td></tr>\n"
}

///|
fn pre_hunk_note(buf : StringBuilder, note : HunkNote) -> Unit {
  buf <+
    "<span class=\"hunk-note\"><b class=\"hunk-note-title\">\{esc(note.title)}</b>: \{esc(note.body)}</span>\n"
}

///|
fn split_row(
  buf : StringBuilder,
  old_number : Int?,
  old_class : String,
  old_html : String,
  new_number : Int?,
  new_class : String,
  new_html : String,
  line_numbers : Bool,
) -> Unit {
  if line_numbers {
    buf <+
      "<tr><td class=\"line-number old-line-number\">\{line_number_text(old_number)}</td><td class=\"\{old_class}\">\{old_html}</td><td class=\"line-number new-line-number\">\{line_number_text(new_number)}</td><td class=\"\{new_class}\">\{new_html}</td></tr>\n"
  } else {
    buf <+
      "<tr><td class=\"\{old_class}\">\{old_html}</td><td class=\"\{new_class}\">\{new_html}</td></tr>\n"
  }
}

///|
fn split_ignored_row(
  buf : StringBuilder,
  row : @tokdiff.DiffRow,
  line_numbers : Bool,
) -> Unit {
  match row {
    Paired(old_line, new_line) =>
      split_row(
        buf,
        Some(old_line.index + 1),
        "ctx ignored",
        line_html(old_line, "wd"),
        Some(new_line.index + 1),
        "ctx ignored",
        line_html(new_line, "wa"),
        line_numbers,
      )
    OldOnly(old_line) =>
      split_row(
        buf,
        Some(old_line.index + 1),
        "ctx ignored",
        line_html(old_line, "wd"),
        None,
        "empty",
        "",
        line_numbers,
      )
    NewOnly(new_line) =>
      split_row(
        buf,
        None,
        "empty",
        "",
        Some(new_line.index + 1),
        "ctx ignored",
        line_html(new_line, "wa"),
        line_numbers,
      )
  }
}

///|
fn append_split_hunk(
  buf : StringBuilder,
  hunk : @tokdiff.DiffHunk,
  hunk_index : Int,
  line_numbers : Bool,
  hunk_notes : ArrayView[HunkNote?],
) -> Unit {
  let header = @common.hunk_header(
    hunk.old_start,
    hunk.old_len,
    hunk.new_start,
    hunk.new_len,
  )
  if line_numbers {
    buf <+
      "<tr><td class=\"hunk-header\" colspan=\"4\">\{esc(header)}</td></tr>\n"
  } else {
    buf <+
      "<tr><td class=\"hunk-header\" colspan=\"2\">\{esc(header)}</td></tr>\n"
  }
  if hunk_note_at(hunk_notes, hunk_index) is Some(note) {
    table_hunk_note(buf, note, if line_numbers { 4 } else { 2 })
  }
  for block in hunk.blocks {
    match block {
      ContextBlock(lines) =>
        for line in lines {
          split_row(
            buf,
            Some(line.old_index + 1),
            "ctx",
            esc(line.text),
            Some(line.new_index + 1),
            "ctx",
            esc(line.text),
            line_numbers,
          )
        }
      ChangeBlock(rows) =>
        for row in rows {
          match row {
            Paired(old_line, new_line) =>
              split_row(
                buf,
                Some(old_line.index + 1),
                if line_is_ignored(old_line) {
                  "ctx ignored"
                } else {
                  "del"
                },
                line_html(old_line, "wd"),
                Some(new_line.index + 1),
                if line_is_ignored(new_line) {
                  "ctx ignored"
                } else {
                  "add"
                },
                line_html(new_line, "wa"),
                line_numbers,
              )
            OldOnly(old_line) =>
              split_row(
                buf,
                Some(old_line.index + 1),
                if line_is_ignored(old_line) {
                  "ctx ignored"
                } else {
                  "del"
                },
                line_html(old_line, "wd"),
                None,
                "empty",
                "",
                line_numbers,
              )
            NewOnly(new_line) =>
              split_row(
                buf,
                None,
                "empty",
                "",
                Some(new_line.index + 1),
                if line_is_ignored(new_line) {
                  "ctx ignored"
                } else {
                  "add"
                },
                line_html(new_line, "wa"),
                line_numbers,
              )
          }
        }
      IgnoredBlock(rows) =>
        for row in rows {
          split_ignored_row(buf, row, line_numbers)
        }
    }
  }
}

///|
/// Render a calculated diff as a GitHub-style side-by-side HTML table.
pub fn render_side_by_side(
  document : @tokdiff.DiffDocument,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> String {
  let buf = StringBuilder::new()
  buf <+ "<table class=\"split\">\n"
  for hunk_index, hunk in document.hunks {
    append_split_hunk(buf, hunk, hunk_index, line_numbers, hunk_notes)
  }
  buf <+ "</table>\n"
  buf.to_string()
}

///|
/// Render every calculated hunk as its own side-by-side HTML table.
pub fn render_side_by_side_hunks(
  document : @tokdiff.DiffDocument,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> Array[String] {
  let rendered : Array[String] = []
  for hunk_index, hunk in document.hunks {
    let buf = StringBuilder::new()
    buf <+ "<table class=\"split\">\n"
    append_split_hunk(buf, hunk, hunk_index, line_numbers, hunk_notes)
    buf <+ "</table>\n"
    rendered.push(buf.to_string())
  }
  rendered
}

///|
fn unified_text_line(
  buf : StringBuilder,
  class_name : String,
  prefix : String,
  body : String,
) -> Unit {
  buf <+ "<span class=\"\{class_name}\">\{prefix}\{body}</span>\n"
}

///|
fn unified_numbered_line(
  buf : StringBuilder,
  class_name : String,
  prefix : String,
  old_number : Int?,
  new_number : Int?,
  body : String,
) -> Unit {
  buf <+
    "<tr><td class=\"line-number old-line-number\">\{line_number_text(old_number)}</td><td class=\"line-number new-line-number\">\{line_number_text(new_number)}</td><td class=\"\{class_name}\">\{prefix}\{body}</td></tr>\n"
}

///|
fn unified_old_line(
  buf : StringBuilder,
  line : @tokdiff.DiffLine,
  line_numbers : Bool,
) -> Unit {
  if line_is_ignored(line) {
    unified_ignored_line(buf, line, Some(line.index + 1), None, line_numbers)
    return
  }
  let body = line_html(line, "wd")
  if line_numbers {
    unified_numbered_line(buf, "del", "-", Some(line.index + 1), None, body)
  } else {
    unified_text_line(buf, "del", "-", body)
  }
}

///|
fn unified_new_line(
  buf : StringBuilder,
  line : @tokdiff.DiffLine,
  line_numbers : Bool,
) -> Unit {
  if line_is_ignored(line) {
    unified_ignored_line(buf, line, None, Some(line.index + 1), line_numbers)
    return
  }
  let body = line_html(line, "wa")
  if line_numbers {
    unified_numbered_line(buf, "add", "+", None, Some(line.index + 1), body)
  } else {
    unified_text_line(buf, "add", "+", body)
  }
}

///|
fn unified_ignored_line(
  buf : StringBuilder,
  line : @tokdiff.DiffLine,
  old_number : Int?,
  new_number : Int?,
  line_numbers : Bool,
) -> Unit {
  let body = line_html(line, "wa")
  if line_numbers {
    unified_numbered_line(buf, "ctx ignored", " ", old_number, new_number, body)
  } else {
    unified_text_line(buf, "ctx ignored", " ", body)
  }
}

///|
fn append_unified_ignored_row(
  buf : StringBuilder,
  row : @tokdiff.DiffRow,
  line_numbers : Bool,
) -> Unit {
  match row {
    Paired(old_line, new_line) =>
      if old_line.text() == new_line.text() {
        unified_ignored_line(
          buf,
          old_line,
          Some(old_line.index + 1),
          Some(new_line.index + 1),
          line_numbers,
        )
      } else {
        unified_ignored_line(
          buf,
          old_line,
          Some(old_line.index + 1),
          None,
          line_numbers,
        )
        unified_ignored_line(
          buf,
          new_line,
          None,
          Some(new_line.index + 1),
          line_numbers,
        )
      }
    OldOnly(old_line) =>
      unified_ignored_line(
        buf,
        old_line,
        Some(old_line.index + 1),
        None,
        line_numbers,
      )
    NewOnly(new_line) =>
      unified_ignored_line(
        buf,
        new_line,
        None,
        Some(new_line.index + 1),
        line_numbers,
      )
  }
}

///|
fn append_unified_hunk(
  buf : StringBuilder,
  hunk : @tokdiff.DiffHunk,
  hunk_index : Int,
  line_numbers : Bool,
  hunk_notes : ArrayView[HunkNote?],
) -> Unit {
  let header = @common.hunk_header(
    hunk.old_start,
    hunk.old_len,
    hunk.new_start,
    hunk.new_len,
  )
  if line_numbers {
    buf <+
      "<tr><td class=\"hunk-header\" colspan=\"3\">\{esc(header)}</td></tr>\n"
  } else {
    buf <+ "<span class=\"hunk-header\">\{esc(header)}</span>\n"
  }
  if hunk_note_at(hunk_notes, hunk_index) is Some(note) {
    if line_numbers {
      table_hunk_note(buf, note, 3)
    } else {
      pre_hunk_note(buf, note)
    }
  }
  for block in hunk.blocks {
    match block {
      ContextBlock(lines) =>
        for line in lines {
          if line_numbers {
            unified_numbered_line(
              buf,
              "ctx",
              " ",
              Some(line.old_index + 1),
              Some(line.new_index + 1),
              esc(line.text),
            )
          } else {
            unified_text_line(buf, "ctx", " ", esc(line.text))
          }
        }
      ChangeBlock(rows) => {
        for row in rows {
          match row {
            Paired(old_line, _) | OldOnly(old_line) =>
              unified_old_line(buf, old_line, line_numbers)
            NewOnly(_) => ()
          }
        }
        for row in rows {
          match row {
            Paired(_, new_line) | NewOnly(new_line) =>
              unified_new_line(buf, new_line, line_numbers)
            OldOnly(_) => ()
          }
        }
      }
      IgnoredBlock(rows) =>
        for row in rows {
          append_unified_ignored_row(buf, row, line_numbers)
        }
    }
  }
}

///|
/// Render a calculated diff as unified HTML.
pub fn render_unified(
  document : @tokdiff.DiffDocument,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> String {
  let buf = StringBuilder::new()
  if line_numbers {
    buf <+ "<table class=\"unified numbered\">\n"
  } else {
    buf <+ "<pre class=\"unified\">\n"
  }
  for hunk_index, hunk in document.hunks {
    append_unified_hunk(buf, hunk, hunk_index, line_numbers, hunk_notes)
  }
  if line_numbers {
    buf <+ "</table>\n"
  } else {
    buf <+ "</pre>\n"
  }
  buf.to_string()
}

///|
/// Render every calculated hunk as its own unified HTML block.
pub fn render_unified_hunks(
  document : @tokdiff.DiffDocument,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> Array[String] {
  let rendered : Array[String] = []
  for hunk_index, hunk in document.hunks {
    let buf = StringBuilder::new()
    if line_numbers {
      buf <+ "<table class=\"unified numbered\">\n"
    } else {
      buf <+ "<pre class=\"unified\">\n"
    }
    append_unified_hunk(buf, hunk, hunk_index, line_numbers, hunk_notes)
    if line_numbers {
      buf <+ "</table>\n"
    } else {
      buf <+ "</pre>\n"
    }
    rendered.push(buf.to_string())
  }
  rendered
}

///|
/// GitHub-style split view of a MoonBit-aware diff.
pub fn side_by_side_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
  ignore_comments? : Bool = false,
) -> String {
  render_side_by_side(
    @tokdiff.diff(old~, new~, context~, line_cleanup~, ignore_comments~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Render each MoonBit-aware hunk as its own split HTML table.
pub fn side_by_side_hunks_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
  ignore_comments? : Bool = false,
) -> Array[String] {
  render_side_by_side_hunks(
    @tokdiff.diff(old~, new~, context~, line_cleanup~, ignore_comments~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Unified HTML view of a MoonBit-aware diff.
pub fn unified_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
  ignore_comments? : Bool = false,
) -> String {
  render_unified(
    @tokdiff.diff(old~, new~, context~, line_cleanup~, ignore_comments~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Render each MoonBit-aware hunk as its own unified HTML block.
pub fn unified_hunks_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
  ignore_comments? : Bool = false,
) -> Array[String] {
  render_unified_hunks(
    @tokdiff.diff(old~, new~, context~, line_cleanup~, ignore_comments~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// GitHub-style split view of a plain Patience line diff.
pub fn side_by_side_line_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> String {
  render_side_by_side(
    @tokdiff.line_diff(old~, new~, context~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Render each plain Patience hunk as its own split HTML table.
pub fn side_by_side_line_hunks_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> Array[String] {
  render_side_by_side_hunks(
    @tokdiff.line_diff(old~, new~, context~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Unified HTML view of a plain Patience line diff.
pub fn unified_line_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> String {
  render_unified(
    @tokdiff.line_diff(old~, new~, context~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Render each plain Patience hunk as its own unified HTML block.
pub fn unified_line_hunks_html(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_numbers? : Bool = false,
  hunk_notes? : ArrayView[HunkNote?] = [],
) -> Array[String] {
  render_unified_hunks(
    @tokdiff.line_diff(old~, new~, context~),
    line_numbers~,
    hunk_notes~,
  )
}

///|
/// Wrap rendered diff HTML in a complete standalone page with default styles.
pub fn html_page(title~ : String, body : String) -> String {
  let buf = StringBuilder::new()
  buf <+ "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">"
  buf <+ "<title>\{esc(title)}</title><style>\n"
  buf <+ "body { font-family: monospace; }\n"
  buf <+ ".hunk-header { color: #00a; }\n"
  buf <+ ".del { background: #ffecec; }\n"
  buf <+ ".add { background: #eaffea; }\n"
  buf <+ "td.empty { background: #fafafa; }\n"
  buf <+ "b.wd { background: #f8b4b4; font-weight: normal; }\n"
  buf <+ "b.wa { background: #97e0a0; font-weight: normal; }\n"
  buf <+ ".ignored-context { background: white; font-weight: normal; }\n"
  buf <+ "pre.unified span { display: block; }\n"
  buf <+
    "table.split, table.unified { border-collapse: collapse; width: 100%; }\n"
  buf <+ "table.split td { width: 50%; vertical-align: top;\n"
  buf <+ "  white-space: pre-wrap; border: 1px solid #eee; }\n"
  buf <+
    "table.unified td { vertical-align: top; white-space: pre-wrap; border: 1px solid #eee; }\n"
  buf <+ "td.line-number { width: 1%; min-width: 3em; padding: 0 .5em;\n"
  buf <+
    "  color: #6e7781; background: #f6f8fa; text-align: right; user-select: none; }\n"
  buf <+ "table.unified td:last-child { width: 100%; }\n"
  buf <+ "</style></head><body>\n"
  buf <+ "\{body}"
  buf <+ "</body></html>\n"
  buf.to_string()
}
