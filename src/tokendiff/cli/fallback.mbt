///|
fn fallback_to_linediff(old~ : String, new~ : String) -> String {
  let buf = StringBuilder::new(size_hint=new.length() + old.length())
  let blue = @chalk.chalk().color(Blue).modifier(Bold)
  let red = @chalk.chalk().color(Red).modifier(Bold)
  let green = @chalk.chalk().color(Green).modifier(Bold)
  let gray = @chalk.chalk().color(BlackBright)
  let hunks = @line_diff.line_diff(old~, new~)
  for hunk in hunks {
    let header = hunk.0.to_string()
    buf.write_string("  ")
    buf.write_string(blue.render(header))
    buf.write_char('\n')
    for edit in hunk.1 {
      match edit {
        (Ins, line) => {
          buf.write_string(green.render("+ "))
          buf.write_string(green.render(line))
        }
        (Del, line) => {
          buf.write_string(red.render("- "))
          buf.write_string(red.render(line))
        }
        (Eql, line) => {
          buf.write_string("  ")
          buf.write_string(gray.render(line))
        }
      }
      buf.write_char('\n')
    }
    buf.write_char('\n')
    buf.write_char('\n')
  }
  buf.to_string()
}
