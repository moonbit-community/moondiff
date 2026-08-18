///|
fn append_diff_line(
  buf : StringBuilder,
  prefix : String,
  line : @model.DiffLine,
) -> Unit {
  buf <+ "\{prefix}"
  for segment in line.segments {
    buf <+ "\{segment.text}"
  }
  buf <+ "\n"
}

///|
fn append_change_line(
  buf : StringBuilder,
  prefix : String,
  line : @model.DiffLine,
) -> Unit {
  let ignored = !line.segments.is_empty() &&
    line.segments.all(segment => segment.kind is Ignored)
  append_diff_line(buf, if ignored { " " } else { prefix }, line)
}

///|
fn append_ignored_row(buf : StringBuilder, row : @model.DiffRow) -> Unit {
  match row {
    Paired(old_line, new_line) =>
      if old_line.text() == new_line.text() {
        append_diff_line(buf, " ", old_line)
      } else {
        append_diff_line(buf, " ", old_line)
        append_diff_line(buf, " ", new_line)
      }
    OldOnly(line) | NewOnly(line) => append_diff_line(buf, " ", line)
  }
}

///|
fn render_hunk(hunk : @model.DiffHunk) -> String {
  let buf = StringBuilder::new()
  buf <+
    "\{@common.hunk_header(hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len)}\n"
  for block in hunk.blocks {
    match block {
      ContextBlock(lines) =>
        for line in lines {
          buf <+ " \{line.text}\n"
        }
      ChangeBlock(rows) => {
        for row in rows {
          match row {
            Paired(old_line, _) | OldOnly(old_line) =>
              append_change_line(buf, "-", old_line)
            NewOnly(_) => ()
          }
        }
        for row in rows {
          match row {
            Paired(_, new_line) | NewOnly(new_line) =>
              append_change_line(buf, "+", new_line)
            OldOnly(_) => ()
          }
        }
      }
      IgnoredBlock(rows) =>
        for row in rows {
          append_ignored_row(buf, row)
        }
    }
  }
  buf.to_string()
}

///|
/// Render every hunk in a calculated diff as unified patch text.
pub fn render_unified_hunks(document : @model.DiffDocument) -> Array[String] {
  document.hunks.map(render_hunk)
}

///|
/// Return unified patch hunks for a MoonBit-aware diff.
pub fn unified_hunks(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
  line_cleanup? : Bool = false,
  ignore_comments? : Bool = false,
) -> Array[String] {
  render_unified_hunks(
    @tokdiff.diff(old~, new~, context~, line_cleanup~, ignore_comments~),
  )
}

///|
/// Return unified patch hunks for a plain Patience line diff.
pub fn unified_line_hunks(
  old~ : ArrayView[String],
  new~ : ArrayView[String],
  context? : Int = 3,
) -> Array[String] {
  render_unified_hunks(@tokdiff.line_diff(old~, new~, context~))
}
