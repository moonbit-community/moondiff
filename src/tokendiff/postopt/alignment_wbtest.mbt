///|
test "compute_common_prefix_length" {
  let dummy_loc = @basic.Location::{
    start: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
    end: @basic.Position::{ lnum: -1, fname: "dummy", bol: -1, cnum: -1 },
  }
  fn id(ch : Char) -> MbtToken {
    MbtToken::Visible(kind=@tokens.TokenKind::TK_LIDENT, loc=dummy_loc, repr=[
      ch,
    ])
  }

  inspect(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('a'),
      id('b'),
      id('d'),
    ]),
    content="2",
  )
  inspect(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('a'),
      id('b'),
      id('c'),
    ]),
    content="3",
  )
  inspect(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('x'),
      id('y'),
      id('z'),
    ]),
    content="0",
  )
  inspect(
    compute_common_prefix_length([], [id('a'), id('b'), id('c')]),
    content="0",
  )
  inspect(
    compute_common_prefix_length([id('a'), id('b'), id('c')], []),
    content="0",
  )
  inspect(compute_common_prefix_length([], []), content="0")
}
