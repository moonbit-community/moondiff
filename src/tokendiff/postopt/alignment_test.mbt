///|
let dummy_loc : @basic.Location = @basic.Location::{
  start: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
  end: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
}

///|
fn ids(strs : Array[String]) -> Array[@mbttoken.MbtToken] {
  let result = []
  for str in strs {
    result.push(
      @mbttoken.MbtToken::Visible(
        kind=@tokens.TokenKind::TK_LIDENT,
        loc=dummy_loc,
        repr=str.to_array(),
      ),
    )
  }
  return result
}

///|
test {
  @json.inspect(
    @postopt.align_edit_boundaries([
      Delete(old=ids(["xyz", "wuv"])),
      Insert(new=ids(["aaa", "bbb", "ccc"])),
      Equal(old=[Invisible([' '])], new=[Invisible([' ', '\n'])]),
    ]),
    content=[
      [
        "---",
        [
          { "kind": "LIDENT", "repr": "xyz" },
          { "kind": "LIDENT", "repr": "wuv" },
          " ",
        ],
      ],
      [
        "+++",
        [
          { "kind": "LIDENT", "repr": "aaa" },
          { "kind": "LIDENT", "repr": "bbb" },
          { "kind": "LIDENT", "repr": "ccc" },
          " \n",
        ],
      ],
    ],
  )
}
