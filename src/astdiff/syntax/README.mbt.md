# `myfreess/moondiff/astdiff/syntax`

Defines a small syntax tree (`Syntax`) with attached, mutable metadata (`SyntaxInfo`) used by the AST diff layer. The `init_all_info` pass assigns ids, parent/sibling links, and “content ids”.

## Examples

```mbt check
///|
test "construct a tiny syntax tree and initialize metadata" {
  let pos = [@span.SingleLineSpan::{ line: 1, start_col: 0, end_col: 1 }]
  let leaf = @syntax.Syntax::atom(
    content="x",
    position=pos,
    kind=@syntax.AtomKind::Normal,
  )
  let root = @syntax.Syntax::simple_list(
    open_position=[],
    children=[leaf],
    close_position=[],
  )

  let lhs = [root]
  let rhs : Array[@syntax.Syntax] = []
  @syntax.init_all_info(lhs[:], rhs[:])

  assert_eq(lhs[0].id() != @uint.max_value, true)
}

///|
test "collect comment positions" {
  let pos = [@span.SingleLineSpan::{ line: 2, start_col: 3, end_col: 5 }]
  let comment = @syntax.Syntax::atom(
    content="// hi",
    position=pos,
    kind=@syntax.AtomKind::Comment,
  )
  @json.inspect(@syntax.Syntax::comment_positions([comment]), content=[
    { "line": 2, "start_col": 3, "end_col": 5 },
  ])
}
```
