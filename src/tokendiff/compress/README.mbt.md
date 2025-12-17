# `myfreess/moondiff/tokendiff/compress`

Post-processes a stream of `Edit[T]` into grouped `Edit[Array[T]]` by merging consecutive operations of the same kind.

## Examples

```mbt check
///|
test "compress consecutive edits" {
  let edits : Array[@edit.Edit[Int]] = [
    @edit.Edit::Delete(old=1),
    @edit.Edit::Delete(old=2),
    @edit.Edit::Equal(old=3, new=3),
    @edit.Edit::Insert(new=4),
    @edit.Edit::Insert(new=5),
  ]
  @json.inspect(@compress.compress_edits(edits[:]), content=[
    { "delete": [1, 2] },
    { "equal": { "old": [3], "new": [3] } },
    { "insert": [4, 5] },
  ])
}
```
