# `myfreess/moondiff/tokendiff/cli`

The `tokendiff` command-line interface (main package) that renders diffs for MoonBit sources.

## Examples

```mbt check
///|
test "CLI package has a working diff pipeline" {
  let old = @mbttoken.MbtToken::from_str("let x = 1\n")
  let new = @mbttoken.MbtToken::from_str("let x = 2\n")
  let edits = @diff_with_opt.diff_with_opt(old=old[:], new=new[:])
  assert_eq(edits.length() >= 1, true)

  let grouped = @line_group.line_group("a\nb\nc\n", "a\nB\nc\n")
  assert_eq(grouped is Some(_), true)
}
```
