///|
// Split source text using universal newline rules while stopping before the
// result exceeds `max_lines`. Keeping this helper local avoids depending on a
// moondiff internal package across the workspace's module boundary.
fn split_source_lines_bounded(
  source : String,
  max_lines~ : Int,
) -> Array[String]? {
  if max_lines < 1 {
    return None
  }
  let chars = source.to_array()
  let lines : Array[String] = []
  let mut line_start = 0
  let mut index = 0
  while index < chars.length() {
    match chars[index] {
      '\r' => {
        if lines.length() >= max_lines {
          return None
        }
        lines.push(String::from_array(chars[line_start:index].to_owned()))
        index += 1
        if index < chars.length() && chars[index] == '\n' {
          index += 1
        }
        line_start = index
      }
      '\n' => {
        if lines.length() >= max_lines {
          return None
        }
        lines.push(String::from_array(chars[line_start:index].to_owned()))
        index += 1
        line_start = index
      }
      _ => index += 1
    }
  }
  if lines.length() >= max_lines {
    None
  } else {
    lines.push(String::from_array(chars[line_start:].to_owned()))
    Some(lines)
  }
}
