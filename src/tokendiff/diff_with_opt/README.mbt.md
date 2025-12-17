# `myfreess/moondiff/tokendiff/diff_with_opt`

End-to-end token diff pipeline: prefix/suffix peeling (`preopt`) + Myers diff (`myers`) + grouping (`compress`) + boundary alignment (`postopt`).

## Examples

```mbt check
///|
test "diff two token streams" {
  let old = @mbttoken.MbtToken::from_str("let x = 1\n")
  let new = @mbttoken.MbtToken::from_str("let x = 2\n")
  let edits = @diff_with_opt.diff_with_opt(old=old[:], new=new[:])
  assert_eq(edits.length() >= 1, true)
}
```
