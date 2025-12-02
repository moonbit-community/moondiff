///|UUID(0c93d9f9-f1d1-4f4c-98c6-d55e42da960a)
pub enum ChangeKind {
  /// This node is shallowly unchanged. For lists, this means that
  /// the delimiters match, but there may still be some differences
  /// in the children between LHS and RHS.
  Unchanged(Syntax)
  ReplacedComment(lhs~ : Syntax, rhs~ : Syntax)
  ReplacedString(lhs~ : Syntax, rhs~ : Syntax)
  Novel
}

///|UUID(82b3ae5f-3847-41eb-9b50-aca4d45532d3)
pub struct ChangeMap(@hashmap.HashMap[SyntaxId, ChangeKind])

///|UUID(cb577564-5b6e-4c0c-a65c-06ed05ff9047)
pub fn ChangeMap::new() -> Self {
  ChangeMap(@hashmap.HashMap::new())
}

///|UUID(c8846d67-5871-402b-b4aa-d6ba6e55d69f)
pub fn ChangeMap::insert(self : Self, node : Syntax, ck : ChangeKind) -> Unit {
  self.0[node.id()] = ck
}

///|UUID(8944564a-070e-4e74-92c7-9ab4fd70827d)
pub fn ChangeMap::get(self : Self, node : Syntax) -> ChangeKind? {
  self.0.get(node.id())
}

///|UUID(755b7458-0723-4b0e-b275-0f4150f39d35)
pub fn ChangeMap::insert_deep_unchanged(
  self : Self,
  node~ : Syntax,
  opposite_node~ : Syntax,
) -> Unit {
  self.insert(node, ChangeKind::Unchanged(opposite_node))
  if node is Syntax::List(children=node_children, ..) &&
    opposite_node is Syntax::List(children=opposite_children, ..) {
    if node_children.length() == opposite_children.length() {
      for i in 0..<node_children.length() {
        self.insert_deep_unchanged(
          node=node_children[i],
          opposite_node=opposite_children[i],
        )
      }
    } else {
      // lengths don't match; can't go deeper
      panic()
    }
  } else if node is Syntax::Atom(..) && opposite_node is Syntax::Atom(..) {
    // nothing to do
  } else {
    // mismatched kinds; can't go deeper
    panic()
  }
}

///|UUID(effec7a1-ef4e-4712-8c9c-dfbb32de36e4)
pub fn ChangeMap::insert_deep_novel(self : Self, node : Syntax) -> Unit {
  self.insert(node, ChangeKind::Novel)
  if node is Syntax::List(children~, ..) {
    for child in children {
      self.insert_deep_novel(child)
    }
  }
}
