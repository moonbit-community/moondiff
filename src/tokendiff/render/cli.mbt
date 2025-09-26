///|
pub fn cli_rendering(
  edits : ArrayView[Edit[Array[@mbttoken.MbtToken]]],
) -> String {
  let red = @chalk.chalk().color(Red).modifier(Bold)
  let green = @chalk.chalk().color(Green).modifier(Bold)
  let buf = StringBuilder::new(size_hint=edits.length() * 20)
  for edit in edits {
    match edit {
      Delete(old~) =>
        buf.write_string(
          red.render(
            old.iter().map(old => String::from_array(old.to_text())).join(""),
          ),
        )
      Insert(new~) =>
        buf.write_string(
          green.render(
            new.iter().map(new => String::from_array(new.to_text())).join(""),
          ),
        )
      Equal(new~, ..) =>
        buf.write_string(
          new.iter().map(new => String::from_array(new.to_text())).join(""),
        )
    }
  } else {
    buf.to_string()
  }
}
