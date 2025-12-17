# `myfreess/moondiff/tokendiff/edit`

The core edit type used across token- and line-based diffs.

## Examples

```mbt check
///|
test "Edit JSON shape" {
  let edits : Array[@edit.Edit[Int]] = [
    @edit.Edit::Delete(old=1),
    @edit.Edit::Equal(old=2, new=2),
    @edit.Edit::Insert(new=3),
  ]
  @json.inspect(edits, content=[
    { "delete": 1 },
    { "equal": { "old": 2, "new": 2 } },
    { "insert": 3 },
  ])
}
```
