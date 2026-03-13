///|UUID(3a563545-9849-44b2-be1f-72c7436470d9)
let dummy_loc : @basic.Location = @basic.Location::{
  start: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
  end: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
}

///|UUID(43edad98-a1de-4501-a74a-257568e62e81)
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

///|UUID(b0df4f3c-109e-4a40-a47d-fe14816c6981)
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

///|UUID(5e0f815c-2802-4413-a038-d26b7a2fdb53)
test {
  let edits = @postopt.align_edit_boundaries([
    Delete(old=ids(["xyz", "wuv"])),
    Insert(new=ids(["aaa", "bbb", "ccc"])),
    Equal(old=[Invisible([1])], new=[Invisible([1, 0])]),
  ]).flatten_edits()
  assert_true(
    edits
    is [
      Delete(old=[Visible(kind=TK_LIDENT, repr=['x', 'y', 'z'], ..)]),
      Delete(old=[Visible(kind=TK_LIDENT, repr=['w', 'u', 'v'], ..)]),
      Equal(old=[Invisible([1])], new=[]),
      Insert(new=[Visible(kind=TK_LIDENT, repr=['a', 'a', 'a'], ..)]),
      Insert(new=[Visible(kind=TK_LIDENT, repr=['b', 'b', 'b'], ..)]),
      Insert(new=[Visible(kind=TK_LIDENT, repr=['c', 'c', 'c'], ..)]),
      Insert(new=[Invisible([1, 0])]),
    ],
  )
}
