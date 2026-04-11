///|UUID(96973d79-78b3-4bff-93af-2bb02aa3f6e5)
fn piediff_old_range(edit : @piediff.Edit) -> (Int, Int) {
  match edit {
    @piediff.Edit::Insert(old_index~, ..) => (old_index, old_index)
    @piediff.Edit::Delete(old_index~, len~, ..) => (old_index, old_index + len)
    @piediff.Edit::Equal(old_index~, len~, ..) => (old_index, old_index + len)
  }
}

///|UUID(6f5e783f-6629-4da3-9b7a-3e3e14e08e52)
fn piediff_new_range(edit : @piediff.Edit) -> (Int, Int) {
  match edit {
    @piediff.Edit::Insert(new_index~, len~, ..) => (new_index, new_index + len)
    @piediff.Edit::Delete(new_index~, ..) => (new_index, new_index)
    @piediff.Edit::Equal(new_index~, len~, ..) => (new_index, new_index + len)
  }
}

///|UUID(30036b28-9c0f-46ba-bfee-463def66f9c8)
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
  let mut old_beginning = first_old_start + 1
  let mut new_beginning = first_new_start + 1
  let old_len = old_end - first_old_start
  let new_len = new_end - first_new_start
  let old_range = if old_len == 1 {
    old_beginning.to_string()
  } else {
    if old_len == 0 {
      old_beginning -= 1
    }
    "\{old_beginning},\{old_len}"
  }
  let new_range = if new_len == 1 {
    new_beginning.to_string()
  } else {
    if new_len == 0 {
      new_beginning -= 1
    }
    "\{new_beginning},\{new_len}"
  }
  "@@ -\{old_range} +\{new_range} @@"
}

///|UUID(16eae731-0207-49c1-ae1b-7a4928772592)
fn fallback_to_linediff(old~ : String, new~ : String) -> String {
  let buf = StringBuilder::new(size_hint=new.length() + old.length())
  let blue = @chalk.chalk().color(Blue).modifier(Bold)
  let red = @chalk.chalk().color(Red).modifier(Bold)
  let green = @chalk.chalk().color(Green).modifier(Bold)
  let gray = @chalk.chalk().color(BlackBright)
  let old_lines = old.split("\n").collect()
  let new_lines = new.split("\n").collect()
  let diff = @piediff.Diff(old=old_lines, new=new_lines)
  let hunks = diff.group()
  for hunk in hunks {
    let header = render_piediff_hunk_header(hunk.edits)
    buf.write_string("  ")
    buf.write_string(blue.render(header))
    buf.write_char('\n')
    for edit in hunk.edits {
      match edit {
        @piediff.Edit::Insert(new_index~, len~, ..) =>
          for i in 0..<len {
            let line_no = new_index + i
            buf.write_string(green.render("+ "))
            buf.write_string(green.render(new_lines[line_no]))
            buf.write_char('\n')
          }
        @piediff.Edit::Delete(old_index~, len~, ..) =>
          for i in 0..<len {
            let line_no = old_index + i
            buf.write_string(red.render("- "))
            buf.write_string(red.render(old_lines[line_no]))
            buf.write_char('\n')
          }
        @piediff.Edit::Equal(old_index~, len~, ..) =>
          for i in 0..<len {
            let line_no = old_index + i
            buf.write_string("  ")
            buf.write_string(gray.render(old_lines[line_no]))
            buf.write_char('\n')
          }
      }
    }
    buf.write_char('\n')
    buf.write_char('\n')
  }
  buf.to_string()
}
