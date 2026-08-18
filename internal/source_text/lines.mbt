///|
/// Return half-open character ranges for lines separated by LF, CRLF, or CR.
/// Newline characters are excluded and a terminator retains a final empty
/// range.
pub fn line_ranges(source : String) -> Array[(Int, Int)] {
  let chars = source.to_array()
  let ranges : Array[(Int, Int)] = []
  let mut line_start = 0
  let mut index = 0
  while index < chars.length() {
    match chars[index] {
      '\r' => {
        ranges.push((line_start, index))
        index += 1
        if index < chars.length() && chars[index] == '\n' {
          index += 1
        }
        line_start = index
      }
      '\n' => {
        ranges.push((line_start, index))
        index += 1
        line_start = index
      }
      _ => index += 1
    }
  }
  ranges.push((line_start, chars.length()))
  ranges
}

///|
/// Split source text using universal newline rules. LF, CRLF, and CR each
/// terminate one line, and a terminating newline retains the final empty line.
/// Empty input is represented by one empty line; diff callers that model an
/// empty file as zero lines should handle that policy at their boundary.
pub fn split_lines(source : String) -> Array[String] {
  let chars = source.to_array()
  let lines : Array[String] = []
  for range in line_ranges(source) {
    let (start, end_) = range
    lines.push(String::from_array(chars[start:end_].to_owned()))
  }
  lines
}
