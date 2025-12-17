# `myfreess/moondiff/tokendiff/myers`

Myers diff over arrays (`diff`) producing a sequence of `Edit[T]`.

## Examples

```mbt check
///|
test "diff a small int array" {
  let (changed, edits) = @myers.diff(old=[1, 2, 3], new=[1, 3, 4])
  assert_eq(changed, true)
  @json.inspect(edits, content=[
    { "equal": { "old": 1, "new": 1 } },
    { "delete": 2 },
    { "equal": { "old": 3, "new": 3 } },
    { "insert": 4 },
  ])
}
```
