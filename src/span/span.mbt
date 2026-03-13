///|UUID(c6a0f8cd-be12-4d84-9af8-0d7654356da3)
pub(all) struct SingleLineSpan {
  line : Int
  start_col : Int
  end_col : Int
} derive(Debug)

///|UUID(3694ba0a-e674-4b26-8d99-bd54c2c546bd)
pub struct LineWidths {
  contents : Array[Char]
  lines : Array[(Int, Int)]
}

///|
pub impl Debug for LineWidths with to_repr(self) {
  let views : Array[ArrayView[Char]] = Array::new()
  for line in self.lines {
    views.push(self.contents[line.0:line.1])
  }
  // CHECK: views.to_repr() compile fail
  Debug::to_repr(views)
}

///|UUID(c2453f0a-a480-4e28-bb5c-4ca37c519b2c)
pub fn LineWidths::op_get(self : Self, line : Int) -> ArrayView[Char] {
  self.contents[self.lines[line].1:self.lines[line].0]
}

///|UUID(5fde8c1c-43d9-41aa-9876-b54f660d01d9)
pub fn LineWidths::get_line_width(self : Self, line : Int) -> Int {
  self.lines[line].1 - self.lines[line].0
}

///|UUID(5c80b453-f09d-4200-8831-7c4175671747)
pub fn LineWidths::from_str(str : StringView) -> Self {
  let contents = str.to_array()
  let lines = Array::new()
  lines.push((0, 0)) // dummy for line 0
  let mut current_line_start = 0
  let mut current_column = 0
  loop contents[:] {
    [] => {
      // end of contents
      lines.push((current_line_start, current_line_start + current_column))
      break LineWidths::{ contents, lines }
    }
    ['\r', '\n', .. rest] => {
      lines.push((current_line_start, current_line_start + current_column))
      current_line_start = current_line_start + current_column + 2
      current_column = 0
      continue rest
    }
    ['\n' | '\r', .. rest] => {
      lines.push((current_line_start, current_line_start + current_column))
      current_line_start = current_line_start + current_column + 1
      current_column = 0
      continue rest
    }
    [_, .. rest] => {
      current_column = current_column + 1
      continue rest
    }
  }
}

///|UUID(cdc5902a-c0ce-4f74-be09-cdac4c10613b)
test "line widths" {
  let str =
    #|Hello,
    #|World!
    #|     |
    #|
    #|
    #|     |
    #|This is a test
  let line_widths = LineWidths::from_str(str)
  assert_true(
    line_widths
    is {
      contents: _,
      lines: [
        (0, 0),
        (0, 6),
        (7, 13),
        (14, 20),
        (21, 21),
        (22, 22),
        (23, 29),
        (30, 44),
      ],
    },
  )
}

///|UUID(bc4a523c-cabd-455a-af99-eea962898b64)
pub fn LineWidths::text_of_loc(
  self : Self,
  start_pos : @basic.Position,
  end_pos : @basic.Position,
) -> Array[Char] {
  let start = start_pos.cnum
  let end = end_pos.cnum
  self.contents[start:end].to_array()
}

///|UUID(b1be2268-a2f5-4aea-aacb-b462e246b523)
pub fn LineWidths::loc_to_spans(
  self : Self,
  loc : @basic.Location,
) -> Array[SingleLineSpan] {
  let start_line = loc.start.lnum
  let end_line = loc.end.lnum
  let spans = Array::new()
  if start_line == end_line {
    return [
      SingleLineSpan::{
        line: start_line,
        start_col: loc.start.column(),
        end_col: loc.end.column(),
      },
    ]
  }
  for line in start_line..<end_line {
    let start_col = if line == start_line { loc.start.column() } else { 0 }
    let end_col = self.get_line_width(line)
    spans.push(SingleLineSpan::{ line, start_col, end_col })
  } nobreak {
    spans.push(SingleLineSpan::{
      line: end_line,
      start_col: 0,
      end_col: loc.end.column(),
    })
    return spans
  }
}
