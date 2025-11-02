///|
struct OutputBuf {
  left : StringBuilder
  right : StringBuilder
  mut current_line_width_left : Int
  mut current_line_width_right : Int
}

///|
fn OutputBuf::new() -> OutputBuf {
  OutputBuf::{
    left: StringBuilder::new(),
    right: StringBuilder::new(),
    current_line_width_left: 0,
    current_line_width_right: 0,
  }
}

///|
fn OutputBuf::left(self : OutputBuf) -> StringBuilder {
  self.left
}

///|
fn OutputBuf::right(self : OutputBuf) -> StringBuilder {
  self.right
}

///|
fn OutputBuf::output_string(self : OutputBuf) -> (String, String) {
  (self.left.to_string(), self.right.to_string())
}

///|
let buf_for_coloring : StringBuilder = StringBuilder::new()

///|
fn OutputBuf::write_left(self : OutputBuf, str : ArrayView[Char]) -> Unit {
  buf_for_coloring.reset()
  buf_for_coloring.write_iter(str.iter())
  self
  .left()
  .write_string(@chalk.chalk().color(Red).render(buf_for_coloring.to_string()))
}

///|
fn OutputBuf::write_right(self : OutputBuf, str : ArrayView[Char]) -> Unit {
  buf_for_coloring.reset()
  buf_for_coloring.write_iter(str.iter())
  self
  .right()
  .write_string(
    @chalk.chalk().color(Green).render(buf_for_coloring.to_string()),
  )
}

///|
fn OutputBuf::finish_line_left(self : OutputBuf) -> Unit {
  // TODO: use grapheme cluster aware width calculation
  self.left().write_string(String::make(70 - self.current_line_width_left, ' '))
  self.left().write_string("\n")
  self.current_line_width_left = 0
}

///|
fn OutputBuf::finish_line_right(self : OutputBuf) -> Unit {
  self
  .right()
  .write_string(
    String::make(
      @config.max_line_width.val - self.current_line_width_right,
      ' ',
    ),
  )
  self.right().write_string("\n")
  self.current_line_width_right = 0
}

///|
enum Direction {
  Left(Array[ArrayView[Char]])
  Right(Array[ArrayView[Char]])
  LeftEql(Array[ArrayView[Char]])
  RightEql(Array[ArrayView[Char]])
}

///|
fn OutputBuf::write_texts(self : OutputBuf, direction : Direction) -> Unit {
  match direction {
    Left(texts) =>
      match texts {
        [] => ()
        [single_line] => {
          self.current_line_width_left += single_line.length()
          self.write_left(single_line)
        }
        [single_line, .. rest] => {
          self.current_line_width_left += single_line.length()
          self.write_left(single_line)
          self.finish_line_left()
          for text in rest[:-1] {
            self.current_line_width_left += text.length()
            self.write_left(text)
            self.finish_line_left()
          }
          let last = rest[rest.length() - 1]
          self.current_line_width_left += last.length()
          self.write_left(last)
        }
      }
    Right(texts) =>
      match texts {
        [] => ()
        [single_line] => {
          self.current_line_width_right += single_line.length()
          self.write_right(single_line)
        }
        [single_line, .. rest] => {
          self.current_line_width_right += single_line.length()
          self.write_right(single_line)
          self.finish_line_right()
          for text in rest[:-1] {
            self.current_line_width_right += text.length()
            self.write_right(text)
            self.finish_line_right()
          }
          let last = rest[rest.length() - 1]
          self.current_line_width_right += last.length()
          self.write_right(last)
        }
      }
    LeftEql(left) =>
      match left {
        [] => ()
        [single_line] => {
          self.current_line_width_left += single_line.length()
          self.left().write_iter(single_line.iter())
        }
        [single_line, .. rest] => {
          self.current_line_width_left += single_line.length()
          self.left().write_iter(single_line.iter())
          self.finish_line_left()
          for text in rest[:-1] {
            self.current_line_width_left += text.length()
            self.left().write_iter(text.iter())
            self.finish_line_left()
          }
          let last = rest[rest.length() - 1]
          self.current_line_width_left += last.length()
          self.left().write_iter(last.iter())
        }
      }
    RightEql(right) =>
      match right {
        [] => ()
        [single_line] => {
          self.current_line_width_right += single_line.length()
          self.right().write_iter(single_line.iter())
        }
        [single_line, .. rest] => {
          self.current_line_width_right += single_line.length()
          self.right().write_iter(single_line.iter())
          self.finish_line_right()
          for text in rest[:-1] {
            self.current_line_width_right += text.length()
            self.right().write_iter(text.iter())
            self.finish_line_right()
          }
          let last = rest[rest.length() - 1]
          self.current_line_width_right += last.length()
          self.right().write_iter(last.iter())
        }
      }
  }
}
