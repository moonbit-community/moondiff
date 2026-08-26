///|
// Stateful so bounded consumers can stop before allocating one entry for every
// newline in an untrusted source. Character offsets keep slicing Unicode-safe.
priv struct LineRangeScanner {
  chars : Array[Char]
  mut line_start : Int
  mut index : Int
  mut finished : Bool
}

///|
fn LineRangeScanner::new(source : String) -> Self {
  { chars: source.to_array(), line_start: 0, index: 0, finished: false }
}

///|
fn LineRangeScanner::next(self : Self) -> (Int, Int)? {
  if self.finished {
    return None
  }
  while self.index < self.chars.length() {
    match self.chars[self.index] {
      '\r' => {
        let range = (self.line_start, self.index)
        self.index += 1
        if self.index < self.chars.length() && self.chars[self.index] == '\n' {
          self.index += 1
        }
        self.line_start = self.index
        return Some(range)
      }
      '\n' => {
        let range = (self.line_start, self.index)
        self.index += 1
        self.line_start = self.index
        return Some(range)
      }
      _ => self.index += 1
    }
  }
  self.finished = true
  Some((self.line_start, self.chars.length()))
}

///|
/// Return half-open character ranges for lines separated by LF, CRLF, or CR.
/// Newline characters are excluded and a terminator retains a final empty
/// range.
pub fn line_ranges(source : String) -> Array[(Int, Int)] {
  let scanner = LineRangeScanner::new(source)
  let ranges : Array[(Int, Int)] = []
  while scanner.next() is Some(range) {
    ranges.push(range)
  }
  ranges
}

///|
/// Split source text using universal newline rules. LF, CRLF, and CR each
/// terminate one line, and a terminating newline retains the final empty line.
/// Empty input is represented by one empty line; diff callers that model an
/// empty file as zero lines should handle that policy at their boundary.
pub fn split_lines(source : String) -> Array[String] {
  let scanner = LineRangeScanner::new(source)
  let lines : Array[String] = []
  while scanner.next() is Some(range) {
    let (start, end_) = range
    lines.push(String::from_array(scanner.chars[start:end_].to_owned()))
  }
  lines
}

///|
/// Split source text using universal newline rules, returning `None` as soon
/// as the result would exceed `max_lines`. Empty input still counts as one
/// line, and a terminating newline retains the final empty line.
pub fn split_lines_bounded(source : String, max_lines~ : Int) -> Array[String]? {
  if max_lines < 1 {
    return None
  }
  let scanner = LineRangeScanner::new(source)
  let lines : Array[String] = []
  while scanner.next() is Some(range) {
    if lines.length() >= max_lines {
      return None
    }
    let (start, end_) = range
    lines.push(String::from_array(scanner.chars[start:end_].to_owned()))
  }
  Some(lines)
}
