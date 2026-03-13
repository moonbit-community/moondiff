# `myfreess/moondiff/patch`

Work-in-progress package intended for turning block/token/AST diffs into a higher-level “patch” representation.

## Examples

```mbt check
///|
test "package wiring sanity" {
  let src =
    #|///|UUID(1)
    #|fn foo() -> Int { 1 }
  let blocks : @block.Blocks[String] = @block.create_blocks(src)
  assert_eq(blocks.length(), 1)

  let lw = @span.LineWidths::from_str("hello\nworld\n")
  assert_eq(lw.get_line_width(1), 5)
}
```
