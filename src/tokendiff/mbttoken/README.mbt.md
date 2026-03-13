# `myfreess/moondiff/tokendiff/mbttoken`

Tokenization utilities for MoonBit source: `MbtToken::from_str` lexes source into `MbtToken`s, and `mbttokens_to_string` reconstructs text (used for round-trips and display).

## Examples

```mbt check
///|
test "lex + recover is a round-trip" {
  let src =
    #|let x = 1
    #|let y = x + 1
  let toks = @mbttoken.MbtToken::from_str(src)
  inspect(@mbttoken.mbttokens_to_string(toks), content=src)
}
```
