///|
// Split source text using universal newline rules while stopping before the
// result exceeds `max_lines`. Keeping this helper local avoids depending on a
// moondiff internal package across the workspace's module boundary.
fn split_source_lines_bounded(
  source : String,
  max_lines~ : Int32,
) -> Array[String]? {
  if max_lines < 1 {
    return None
  }
  let lines : Array[String] = []
  for remaining = source[:] {
    // Even an empty remainder is one more line after a trailing newline.
    if lines.length() >= max_lines {
      return None
    }
    match remaining.find_by(c => c == '\r' || c == '\n') {
      Some(i) => {
        lines.push(remaining[:i].to_owned())
        let terminator_length = if remaining[i:].has_prefix("\r\n") {
          2
        } else {
          1
        }
        continue remaining[i + terminator_length:]
      }
      None => {
        lines.push(remaining.to_owned())
        return Some(lines)
      }
    }
  }
}
