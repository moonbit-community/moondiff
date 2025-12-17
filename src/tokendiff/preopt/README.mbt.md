# `myfreess/moondiff/tokendiff/preopt`

Pre-optimization helpers for token diffs, currently focused on peeling off common prefixes/suffixes before running the core diff.

## Examples

```mbt check
///|
test "separate common prefix and suffix" {
  let (prefix, suffix, old_mid, new_mid) = @preopt.separate_common_prefix_and_suffix(
    old=[1, 2, 3, 4],
    new=[1, 2, 9, 4],
  )

  @json.inspect(prefix.to_array(), content=[
    { "equal": { "old": 1, "new": 1 } },
    { "equal": { "old": 2, "new": 2 } },
  ])
  @json.inspect(suffix.to_array(), content=[{ "equal": { "old": 4, "new": 4 } }])
  assert_eq(old_mid.to_array(), [3])
  assert_eq(new_mid.to_array(), [9])
}
```
