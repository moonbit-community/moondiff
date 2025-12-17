# `myfreess/moondiff/span`

Utilities for translating parser `Location`s into per-line spans and for working with line widths derived from source text.

## Examples

```mbt check
///|
test "line widths + spanning a multi-line location" {
  let src =
    #|abc
    #|defg
  let lw = @span.LineWidths::from_str(src)
  assert_eq(lw.get_line_width(1), 3)
  assert_eq(lw.get_line_width(2), 4)

  let loc : @basic.Location = @basic.Location::{
    start: @basic.Position::{ lnum: 1, fname: "x", bol: 0, cnum: 1 }, // "b"
    end: @basic.Position::{ lnum: 2, fname: "x", bol: 4, cnum: 6 }, // "ef"
  }
  @json.inspect(
    lw.loc_to_spans(loc),
    content=[
      { "line": 1, "start_col": 2, "end_col": 3 },
      { "line": 2, "start_col": 0, "end_col": 3 },
    ],
  )
}

///|
test "extract text by absolute positions" {
  let src =
    #|abc
    #|defg
  let lw = @span.LineWidths::from_str(src)
  let start = @basic.Position::{ lnum: 1, fname: "x", bol: 0, cnum: 0 }
  let end_ = @basic.Position::{ lnum: 1, fname: "x", bol: 0, cnum: 3 }
  @json.inspect(lw.text_of_loc(start, end_), content=["a", "b", "c"])
}
```
