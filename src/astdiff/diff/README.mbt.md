# `myfreess/moondiff/astdiff/diff`

Graph-based AST diff primitives built on top of `myfreess/moondiff/astdiff/syntax`.

The main surface area is `ChangeMap` (mapping syntax nodes to a `ChangeKind`) and the Dijkstra-based search used for matching.

## Examples

```mbt check
///|
test "ChangeMap basics" {
  let node = @syntax.Syntax::atom(
    content="foo",
    position=[],
    kind=@syntax.AtomKind::Normal,
  )

  let changes = @diff.ChangeMap::new()
  changes.insert_deep_novel(node)
  assert_eq(changes.get(node) is Some(Novel), true)
}

///|
test "tree_count counts nodes" {
  let n1 = @syntax.Syntax::atom(
    content="x",
    position=[],
    kind=@syntax.AtomKind::Normal,
  )
  let n2 = @syntax.Syntax::atom(
    content="y",
    position=[],
    kind=@syntax.AtomKind::Normal,
  )
  let lhs = [n1, n2]
  let rhs : Array[@syntax.Syntax] = []
  @syntax.init_all_info(lhs[:], rhs[:])

  assert_eq(@diff.tree_count(Some(lhs[0])), 2)
}
```
