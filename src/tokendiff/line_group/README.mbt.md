# `myfreess/moondiff/tokendiff/line_group`

Groups a line-based diff into “normal” runs and “replace” runs, which is useful for rendering compact diffs.

## Examples

```mbt check
///|
test "group a simple replacement" {
  let old =
    #|a
    #|b
    #|c
  let new =
    #|a
    #|B
    #|c
  let groups = @line_group.line_group(old, new)
  assert_eq(groups is Some(_), true)
}
```
