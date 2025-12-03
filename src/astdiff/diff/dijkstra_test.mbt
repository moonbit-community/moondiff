///|UUID(4761b20b-3691-4220-b38a-f164bb52d0ca)
using @syntax {type Syntax}

///|UUID(07773283-18ef-444e-8074-3b5ae7c18565)
fn pos(line : Int) -> Array[@span.SingleLineSpan] {
  [@span.SingleLineSpan::{ line, start_col: 0, end_col: 1 }]
}

///|UUID(7ede833b-3459-4ab9-9357-2b43d49c7f0b)
test "identical atoms" {
  let lhs = Syntax::atom(content="foo", position=pos(0), kind=Normal)
  let rhs = Syntax::atom(content="foo", position=pos(0), kind=Normal)
  @syntax.init_all_info([lhs], [rhs])
  let start = Vertex::new(lhs=Some(lhs), rhs=Some(rhs))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["UnchangedNode", { "depth_difference": 0, "probably_punctuation": false }],
  ])
}

///|UUID(fd9fb746-b732-4a14-a2bb-a4b5e6e31b1c)
test "extra atom lhs" {
  let lhs = [
    Syntax::list(
      open_content="[",
      open_position=pos(0),
      children=[Syntax::atom(content="foo", position=pos(1), kind=Normal)],
      close_content="]",
      close_position=pos(2),
    ),
  ]
  let rhs = [
    Syntax::list(
      open_content="[",
      open_position=pos(0),
      children=[],
      close_content="]",
      close_position=pos(2),
    ),
  ]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["EnterUnchangedDelimiter", { "depth_difference": 0 }],
    "NovelAtomLHS",
  ])
}

///|UUID(63bfd8ce-4e4e-4041-89a7-bf0936f0a8a3)
test "repeated atoms" {
  let lhs = [
    Syntax::list(
      open_content="[",
      open_position=pos(0),
      children=[],
      close_content="]",
      close_position=pos(2),
    ),
  ]
  let rhs = [
    Syntax::list(
      open_content="[",
      open_position=pos(0),
      children=[
        Syntax::atom(content="foo", position=pos(1), kind=Normal),
        Syntax::atom(content="foo", position=pos(2), kind=Normal),
      ],
      close_content="]",
      close_position=pos(3),
    ),
  ]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["EnterUnchangedDelimiter", { "depth_difference": 0 }],
    "NovelAtomRHS",
    "NovelAtomRHS",
  ])
}

///|UUID(16efeba2-03fa-4c1f-8756-ad797b0443af)
test "atom after empty list" {
  let lhs = [
    Syntax::list(
      open_content="[",
      open_position=pos(0),
      children=[
        Syntax::list(
          open_content="(",
          open_position=pos(1),
          children=[],
          close_content=")",
          close_position=pos(2),
        ),
        Syntax::atom(content="foo", position=pos(3), kind=Normal),
      ],
      close_content="]",
      close_position=pos(4),
    ),
  ]
  let rhs = [
    Syntax::list(
      open_content="{",
      open_position=pos(0),
      children=[
        Syntax::list(
          open_content="(",
          open_position=pos(1),
          children=[],
          close_content=")",
          close_position=pos(2),
        ),
        Syntax::atom(content="foo", position=pos(3), kind=Normal),
      ],
      close_content="}",
      close_position=pos(4),
    ),
  ]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    "EnterNovelDelimiterRHS",
    "EnterNovelDelimiterLHS",
    ["UnchangedNode", { "depth_difference": 0, "probably_punctuation": false }],
    ["UnchangedNode", { "depth_difference": 0, "probably_punctuation": false }],
  ])
}

///|UUID(40bde2f0-1867-4589-9c65-67e813a8c6b5)
test "replace similar comment" {
  let lhs = [
    Syntax::atom(content="the quick brown fox", position=pos(1), kind=Comment),
  ]
  let rhs = [
    Syntax::atom(content="the quick brown cat", position=pos(1), kind=Comment),
  ]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["ReplacedComment", { "levenshtein_pct": 84 }],
  ])
}

///|UUID(bc068fb2-54c0-4627-89d9-7195a391979d)
test "replace very different comment" {
  let lhs = [
    Syntax::atom(content="the quick brown fox", position=pos(1), kind=Comment),
  ]
  let rhs = [Syntax::atom(content="foo bar", position=pos(1), kind=Comment)]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["ReplacedComment", { "levenshtein_pct": 11 }],
  ])
}

///|UUID(ab724580-01bb-4933-867c-e07b3a951f6d)
test "replace comment prefer most similar" {
  let lhs = [
    Syntax::atom(content="the quick brown fox", position=pos(1), kind=Comment),
    Syntax::atom(content="the quick brown thing", position=pos(2), kind=Comment),
  ]
  let rhs = [
    Syntax::atom(content="the quick brown fox.", position=pos(1), kind=Comment),
  ]
  @syntax.init_all_info(lhs, rhs)
  let start = Vertex::new(lhs=lhs.get(0), rhs=rhs.get(0))
  let route = shortest_path(start, 0, 3000000)
  let actions = route.iterator().map(pair => pair.0).collect()
  @json.inspect(actions, content=[
    ["ReplacedComment", { "levenshtein_pct": 95 }],
    "NovelAtomLHS",
  ])
}

///|UUID(2ad6eb18-343c-4ce1-9d06-22643a7070d4)
test "mark syntax equal atoms" {
  let lhs = Syntax::atom(content="foo", position=pos(1), kind=Normal)
  let rhs = Syntax::atom(content="foo", position=pos(1), kind=Normal)
  @syntax.init_all_info([lhs], [rhs])
  let change_map = ChangeMap::new()
  mark_syntax(Some(lhs), Some(rhs), change_map, 3000000)
  assert_true(change_map.get(lhs) is Some(Unchanged(_)))
  assert_true(change_map.get(rhs) is Some(Unchanged(_)))
}

///|UUID(4449d01e-bab7-4b3d-a73b-1dafe2b81c70)
test "mark syntax different atoms" {
  let lhs = Syntax::atom(content="foo", position=pos(1), kind=Normal)
  let rhs = Syntax::atom(content="bar", position=pos(1), kind=Normal)
  @syntax.init_all_info([lhs], [rhs])
  let change_map = ChangeMap::new()
  mark_syntax(Some(lhs), Some(rhs), change_map, 3000000)
  assert_true(change_map.get(lhs) is Some(Novel))
  assert_true(change_map.get(rhs) is Some(Novel))
}
