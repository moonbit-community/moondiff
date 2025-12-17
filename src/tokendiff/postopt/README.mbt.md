# `myfreess/moondiff/tokendiff/postopt`

Post-optimization passes for token diffs. `align_edit_boundaries` shifts insert/delete boundaries so edits align better with token structure.

## Examples

```mbt check
///|
test "align_edit_boundaries runs on grouped token edits" {
  let dummy_loc : @basic.Location = @basic.Location::{
    start: @basic.Position::{ lnum: 1, fname: "x", bol: 0, cnum: 0 },
    end: @basic.Position::{ lnum: 1, fname: "x", bol: 0, cnum: 0 },
  }
  fn ident(name : String) -> @mbttoken.MbtToken {
    @mbttoken.MbtToken::Visible(
      kind=@tokens.TokenKind::TK_LIDENT,
      loc=dummy_loc,
      repr=name.to_array(),
    )
  }

  let edits : Array[@edit.Edit[Array[@mbttoken.MbtToken]]] = [
    @edit.Edit::Delete(old=[ident("old")]),
    @edit.Edit::Insert(new=[ident("new")]),
    @edit.Edit::Equal(old=[ident("x")], new=[ident("x")]),
  ]

  let aligned = @postopt.align_edit_boundaries(edits[:])
  assert_eq(aligned.length() >= 1, true)
}
```
