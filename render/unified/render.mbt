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
fn append_neutral_pair(buf : StringBuilder, pair : @model.DiffLinePair) -> Unit {
  match pair {
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
fn append_changed_old(buf : StringBuilder, pair : @model.DiffLinePair) -> Unit {
  match pair {
    Paired(old_line, _) | OldOnly(old_line) =>
      append_change_line(buf, "-", old_line)
    NewOnly(_) => ()
  }
}

///|
fn append_changed_new(buf : StringBuilder, pair : @model.DiffLinePair) -> Unit {
  match pair {
    Paired(_, new_line) | NewOnly(new_line) =>
      append_change_line(buf, "+", new_line)
    OldOnly(_) => ()
  }
}

///|
fn render_hunk(hunk : @model.DiffHunk) -> String {
  let buf = StringBuilder()
  buf <+
    "\{@render.hunk_header(hunk.old_start, hunk.old_len, hunk.new_start, hunk.new_len)}\n"
  let mut index = 0
  while index < hunk.rows.length() {
    match hunk.rows[index] {
      Context(line) => {
        buf <+ " \{line.text}\n"
        index += 1
      }
      Neutral(pair) => {
        append_neutral_pair(buf, pair)
        index += 1
      }
      Changed(_) => {
        let start = index
        while index < hunk.rows.length() && hunk.rows[index] is Changed(_) {
          index += 1
        }
        for row in hunk.rows[start:index] {
          guard row is Changed(pair) else { panic() }
          append_changed_old(buf, pair)
        }
        for row in hunk.rows[start:index] {
          guard row is Changed(pair) else { panic() }
          append_changed_new(buf, pair)
        }
      }
    }
  }
  buf.to_string()
}

///|
/// Render every hunk in one traditional `HunkDocument` as unified patch text.
pub fn render_unified_hunks(document : @model.HunkDocument) -> Array[String] {
  document.hunks.map(render_hunk)
}
