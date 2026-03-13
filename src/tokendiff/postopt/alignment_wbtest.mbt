///|UUID(c42cd0f1-8668-4de3-af43-765d6e49a24a)
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

  assert_true(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('a'),
      id('b'),
      id('d'),
    ])
    is 2,
  )
  assert_true(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('a'),
      id('b'),
      id('c'),
    ])
    is 3,
  )
  assert_true(
    compute_common_prefix_length([id('a'), id('b'), id('c')], [
      id('x'),
      id('y'),
      id('z'),
    ])
    is 0,
  )
  assert_true(
    compute_common_prefix_length([], [id('a'), id('b'), id('c')]) is 0,
  )
  assert_true(
    compute_common_prefix_length([id('a'), id('b'), id('c')], []) is 0,
  )
  assert_true(compute_common_prefix_length([], []) is 0)
}
