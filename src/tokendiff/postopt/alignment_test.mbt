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
fn[T] Array::flatten_edits(
  self : Array[@edit.Edit[Array[T]]],
) -> Array[@edit.Edit[Array[T]]] {
  let result : Array[@edit.Edit[Array[T]]] = []
  for edit in self {
    match edit {
      Delete(old~) =>
        for old in old {
          result.push(Delete(old=[old]))
        }
      Insert(new~) =>
        for new in new {
          result.push(Insert(new=[new]))
        }
      Equal(_) as edit => result.push(edit)
    }
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
    ]).flatten_edits(),
    content=[
      "--- [(LIDENT xyz)]", "--- [(LIDENT wuv)]", "%%% [<| |>]\n%%% []", "+++ [(LIDENT aaa)]",
      "+++ [(LIDENT bbb)]", "+++ [(LIDENT ccc)]", "+++ [<| \n|>]",
    ],
  )
}
