///|UUID(48fe866f-bbe9-48a4-b508-11667742d21b)
/// A vertex in a directed acyclic graph that represents a diff.
///
/// Each vertex represents two pointers: one to the next unmatched LHS
/// syntax, and one to the next unmatched RHS syntax.
///
/// For example, suppose we have `X A` on the LHS and `A` on the
/// RHS. Our start vertex looks like this.
///
/// ```text
/// LHS: X A     RHS: A
///      ^            ^
/// ```
///
/// From this vertex, we could take `Edge::NovelAtomLHS`, bringing
/// us to this vertex.
///
/// ```text
/// LHS: X A     RHS: A
///        ^          ^
/// ```
///
/// Alternatively, we could take the `Edge::NovelAtomRHS`, bringing us
/// to this vertex.
///
/// ```text
/// LHS: X A     RHS: A
///      ^              ^
/// ```
pub struct Vertex {
  neighbours : Ref[Array[(Edge, Vertex)]?]
  predecessor : Ref[(UInt, Vertex)?]
  // TODO: experiment with storing SyntaxId only, and have a HashMap
  // from SyntaxId to Syntax.
  lhs_syntax : Syntax?
  rhs_syntax : Syntax?
  parents : Stack[EnteredDelimiter]
  lhs_parent_id : SyntaxId?
  rhs_parent_id : SyntaxId?
}

///|UUID(78d79d31-041c-4377-b462-2b7734f80082)
/// An edge in our graph, with an associated `cost`(Edge::cost).
///
/// A syntax node can always be marked as novel, so a vertex will have
/// at least a NovelFoo edge. Depending on the syntax nodes of the
/// current `Vertex`, other edges may also be available.
///
/// See `set_neighbours` for all the edges available for a given `Vertex`.
pub enum Edge {
  /// Is this node just punctuation? We penalise this case,
  /// because it's more useful to match e.g. a variable name
  /// than a comma.
  UnchangedNode(depth_difference~ : UInt, probably_punctuation~ : Bool)
  EnterUnchangedDelimiter(depth_difference~ : UInt)
  ReplacedComment(levenshtein_pct~ : UInt)
  ReplacedString(levenshtein_pct~ : UInt)
  NovelAtomLHS
  NovelAtomRHS
  // TODO: An EnterNovelDelimiterBoth edge might help performance
  // rather doing LHS and RHS separately.
  EnterNovelDelimiterLHS
  EnterNovelDelimiterRHS
} derive(ToJson)

///|UUID(879374f4-7c01-44be-8149-5b29afe3bf22)
/// Tracks entering syntax List nodes.
enum EnteredDelimiter {
  /// If we've entered the LHS or RHS separately, we can pop either
  /// side independently.
  ///
  /// Assumes that at least one stack is non-empty.
  PopEither(Stack[Syntax], Stack[Syntax])
  /// If we've entered the LHS and RHS together, we must pop both
  /// sides together too. Otherwise we'd consider the following case to have no changes.
  ///
  /// ```text
  /// Old: (a b c)
  /// New: (a b) c
  /// ```
  PopBoth(Syntax, Syntax)
} derive(Eq)

///|UUID(8b967118-a93e-40d9-a68c-a62c8bb8cffc)
pub impl Show for EnteredDelimiter with output(self, logger) {
  let s = match self {
    PopEither(lhs_delims, rhs_delims) =>
      "PopEither(lhs count: \{lhs_delims.size()}, rhs count: \{rhs_delims.size()})"
    PopBoth(_) => "PopBoth"
  }
  logger.write_string(s)
}

///|UUID(b91c4cfd-ae3a-4e92-9979-1a9130aeb7f8)
pub impl Eq for Vertex with equal(self, other) {
  // Strictly speaking, we should compare the whole
  // EnteredDelimiter stack, not just the immediate
  // parents. By taking the immediate parent, we have
  // vertices with different stacks that are 'equal'.
  //
  // This makes the graph traversal path dependent: the
  // first vertex we see 'wins', and we use it for deciding
  // how we can pop.
  //
  // In practice this seems to work well. The first vertex
  // has the lowest cost, so has the most PopBoth
  // occurrences, which is the best outcome.
  //
  // Handling this properly would require considering many
  // more vertices to be distinct, exponentially increasing
  // the graph size relative to tree depth.
  let b0 = match (self.lhs_syntax, other.lhs_syntax) {
    (Some(s0), Some(s1)) => s0.id() == s1.id()
    (None, None) => self.lhs_parent_id == other.lhs_parent_id
    _ => false
  }
  let b1 = match (self.rhs_syntax, other.rhs_syntax) {
    (Some(s0), Some(s1)) => s0.id() == s1.id()
    (None, None) => self.rhs_parent_id == other.rhs_parent_id
    _ => false
  }
  // We do want to distinguish whether we can pop each side
  // independently though. Without this, if we find a case
  // where we can pop sides together, we don't consider the
  // case where we get a better diff by popping each side
  // separately.
  let b2 = can_pop_either_parent(self.parents) ==
    can_pop_either_parent(other.parents)
  b0 && b1 && b2
}

///|UUID(f9fc997f-6277-4262-aaff-0d867a0f3d24)
pub impl Hash for Vertex with hash_combine(self, hasher) {
  hasher.combine(self.lhs_syntax.map(node => node.id()))
  hasher.combine(self.rhs_syntax.map(node => node.id()))
  hasher.combine(self.lhs_parent_id)
  hasher.combine(self.rhs_parent_id)
  hasher.combine(can_pop_either_parent(self.parents))
}

///|UUID(afad7258-28b5-4bb5-9467-f4f96c0c67ee)
fn can_pop_either_parent(entered : Stack[EnteredDelimiter]) -> Bool {
  entered.peek() is Some(EnteredDelimiter::PopEither(_))
}

///|UUID(e63c3a51-11c4-4535-a83c-1976c578085b)
fn push_both_delimiters(
  entered : Stack[EnteredDelimiter],
  lhs_delim : Syntax,
  rhs_delim : Syntax,
) -> Stack[EnteredDelimiter] {
  entered.push(EnteredDelimiter::PopBoth(lhs_delim, rhs_delim))
}

///|UUID(8c49501e-b4f4-4755-8da7-96b97da680d7)
fn try_pop_both(
  entered : Stack[EnteredDelimiter],
) -> (Syntax, Syntax, Stack[EnteredDelimiter])? {
  match entered.peek() {
    Some(EnteredDelimiter::PopBoth(lhs_delim, rhs_delim)) =>
      entered.pop().map(new_stack => (lhs_delim, rhs_delim, new_stack))
    _ => None
  }
}

///|UUID(bfeceaae-5de9-4dff-bf69-d03e520e5316)
fn try_pop_lhs(
  entered : Stack[EnteredDelimiter],
) -> (Syntax, Stack[EnteredDelimiter])? {
  match entered.peek() {
    Some(EnteredDelimiter::PopEither(lhs_delims, rhs_delims)) =>
      match lhs_delims.peek() {
        Some(lhs_delim) => {
          let mut entered = entered.pop().unwrap()
          let new_lhs_delims = lhs_delims.pop().unwrap()
          if !new_lhs_delims.is_empty() || !rhs_delims.is_empty() {
            entered = entered.push(
              EnteredDelimiter::PopEither(new_lhs_delims, rhs_delims),
            )
          }
          Some((lhs_delim, entered))
        }
        None => None
      }
    _ => None
  }
}

///|UUID(77b805e1-1700-4de7-9db9-e16624ca11a7)
fn try_pop_rhs(
  entered : Stack[EnteredDelimiter],
) -> (Syntax, Stack[EnteredDelimiter])? {
  match entered.peek() {
    Some(EnteredDelimiter::PopEither(lhs_delims, rhs_delims)) =>
      match rhs_delims.peek() {
        Some(rhs_delim) => {
          let mut entered = entered.pop().unwrap()
          let new_rhs_delims = rhs_delims.pop().unwrap()
          if !lhs_delims.is_empty() || !new_rhs_delims.is_empty() {
            entered = entered.push(
              EnteredDelimiter::PopEither(lhs_delims, new_rhs_delims),
            )
          }
          Some((rhs_delim, entered))
        }
        None => None
      }
    _ => None
  }
}

///|UUID(19065316-8274-4845-87a9-b674daa912bd)
fn push_lhs_delimiter(
  entered : Stack[EnteredDelimiter],
  delimiter : Syntax,
) -> Stack[EnteredDelimiter] {
  match entered.peek() {
    Some(PopEither(lhs_delims, rhs_delims)) =>
      entered
      .pop()
      .unwrap()
      .push(EnteredDelimiter::PopEither(lhs_delims.push(delimiter), rhs_delims))
    _ =>
      entered.push(
        EnteredDelimiter::PopEither(Stack::new().push(delimiter), Stack::new()),
      )
  }
}

///|UUID(fa21a9b3-08ed-4bd9-bd07-0d018c696afb)
fn push_rhs_delimiter(
  entered : Stack[EnteredDelimiter],
  delimiter : Syntax,
) -> Stack[EnteredDelimiter] {
  match entered.peek() {
    Some(PopEither(lhs_delims, rhs_delims)) =>
      entered
      .pop()
      .unwrap()
      .push(EnteredDelimiter::PopEither(lhs_delims, rhs_delims.push(delimiter)))
    _ =>
      entered.push(
        EnteredDelimiter::PopEither(Stack::new(), Stack::new().push(delimiter)),
      )
  }
}

///|UUID(5cafcaaf-db94-4978-8706-8d5beefd550b)
fn Vertex::is_end(self : Vertex) -> Bool {
  self.lhs_syntax is None && self.rhs_syntax is None && self.parents.is_empty()
}

///|UUID(66a58d63-0909-4ffb-ac33-5c1bc5933f8e)
pub fn Vertex::new(lhs~ : Syntax?, rhs~ : Syntax?) -> Vertex {
  Vertex::{
    neighbours: Ref::new(None),
    predecessor: Ref::new(None),
    lhs_syntax: lhs,
    rhs_syntax: rhs,
    parents: Stack::new(),
    lhs_parent_id: None,
    rhs_parent_id: None,
  }
}

///|UUID(09439f7f-5de9-4b87-b1be-248e286bd856)
fn Edge::cost(self : Edge) -> UInt {
  match self {
    // Matching nodes is always best.
    UnchangedNode(depth_difference~, probably_punctuation~) => {
      // TODO: Perhaps prefer matching longer strings? It's
      // probably easier to read.

      // The cost for unchanged nodes can be as low as 1,
      // but we penalise nodes that have a different depth
      // difference, capped at 40.
      let base = @cmp.minimum(40U, depth_difference + 1U)

      // If the node is only punctuation, increase the
      // cost. It's better to have unchanged variable names
      // and novel punctuation than the reverse.
      //
      // We want a sufficiently large punctuation cost such
      // that unchanged variables always win, even if there
      // are replacement edges elsewhere.
      //
      // Replacement edges have a cost between 500 and 600,
      // so they can be up to 100 less than two novel nodes.
      // If we have replacements either side of a node
      // (e.g. see comma_and_comment_1.js), then that's
      // potentially a cost difference of 200.
      let incr = if probably_punctuation { 200U } else { 0U }
      base + incr
    }
    // Matching an outer delimiter is good.
    EnterUnchangedDelimiter(depth_difference~) =>
      100 + @cmp.minimum(40, depth_difference + 10)
    // Otherwise, we've added/removed a node.
    NovelAtomLHS | NovelAtomRHS => 300
    EnterNovelDelimiterLHS | EnterNovelDelimiterRHS => 300
    // Replacing a comment is better than treating it as
    // novel. However, since ReplacedComment is an alternative
    // to NovelAtomLHS and NovelAtomRHS, we need to be
    // slightly less than 2 * 300.
    ReplacedComment(levenshtein_pct~) | ReplacedString(levenshtein_pct~) =>
      500 + (100 - levenshtein_pct)
  }
}

///|UUID(2898523a-ab3c-40d8-83a2-2815eae2e728)
fn allocate_if_new(v : Vertex, seen : HashMap[Vertex, Array[Vertex]]) -> Vertex {
  match seen.get(v) {
    Some(existing) => {
      // Don't explore more than two possible parenthesis
      // nestings for each syntax node pair.
      if existing.last() is Some(allocated) && existing.length() > 2 {
        return allocated
      }

      // If we have seen exactly this graph node before, even
      // considering parenthesis matching, return it.
      for existing_node in existing {
        if existing_node.parents == v.parents {
          return existing_node
        }
      }
      existing.push(v)
      v
    }
    None => {
      // use a array to enable experiments with the value
      // of how many possible parenthesis nestings to explore.
      // 
      // never have more than 2 nodes
      let existing = Array::new(capacity=2)
      existing.push(v)
      v
    }
  }
}

///|UUID(a6e967c3-aeb7-453e-bf6e-f308ebcb3b08)
/// Does this node look like punctuation?
///
/// This check is deliberately conservative, because it's hard to
/// accurately recognise punctuation in a language-agnostic way.
fn Syntax::looks_like_punctuation(self : Syntax) -> Bool {
  match self {
    Atom(content~, ..) => content == "," || content == ";" || content == "."
    _ => false
  }
}

///|UUID(e03e2c32-0e95-43a5-996b-37628b179014)
/// Pop as many parents of `lhs_node` and `rhs_node` as
/// possible. Return the new syntax nodes and parents.
fn pop_all_parents(
  lhs_node : Syntax?,
  rhs_node : Syntax?,
  lhs_parent_id : SyntaxId?,
  rhs_parent_id : SyntaxId?,
  parents : Stack[EnteredDelimiter],
) -> (Syntax?, Syntax?, SyntaxId?, SyntaxId?, Stack[EnteredDelimiter]) {
  let mut lhs_node = lhs_node
  let mut rhs_node = rhs_node
  let mut lhs_parent_id = lhs_parent_id
  let mut rhs_parent_id = rhs_parent_id
  let mut parents = parents
  while true {
    if lhs_node is None {
      if try_pop_lhs(parents) is Some((lhs_parent, parents_next)) {
        // Move to next after LHS parent.
        // Continue from sibling of parent.

        lhs_node = lhs_parent.next_sibling()
        lhs_parent_id = lhs_parent.parent().map(Syntax::id)
        parents = parents_next
        continue
      }
    }
    if rhs_node is None {
      if try_pop_rhs(parents) is Some((rhs_parent, parents_next)) {
        // Move to next after RHS parent.
        // Continue from sibling of parent.
        rhs_node = rhs_parent.next_sibling()
        rhs_parent_id = rhs_parent.parent().map(Syntax::id)
        parents = parents_next
        continue
      }
    }
    if lhs_node is None && rhs_node is None {
      // We have exhausted all the nodes on both lists, so we can
      // move up to the parent node.
      // Continue from sibling of parent.

      if try_pop_both(parents) is Some((lhs_parent, rhs_parent, parents_next)) {
        lhs_node = lhs_parent.next_sibling()
        rhs_node = rhs_parent.next_sibling()
        lhs_parent_id = lhs_parent.parent().map(Syntax::id)
        rhs_parent_id = rhs_parent.parent().map(Syntax::id)
        parents = parents_next
        continue
      }
    }
    break
  }
  (lhs_node, rhs_node, lhs_parent_id, rhs_parent_id, parents)
}

///|UUID(7be0974c-4087-481f-8d2c-ccd2665fcdef)
/// Compute the neighbours of `v` if we haven't previously done so,
/// and write them to the .neighbours cell inside `v`.
fn set_neighbours(v : Vertex, seen : HashMap[Vertex, Array[Vertex]]) -> Unit {
  if v.neighbours.val is Some(_) {
    return
  }

  // There are only seven pushes in this function, so that's sufficient.
  let neighbours = Array::new(capacity=7)
  if v.lhs_syntax is Some(lhs_syntax) && v.rhs_syntax is Some(rhs_syntax) {
    if lhs_syntax == rhs_syntax {
      let depth_difference = (lhs_syntax.num_ancestors().reinterpret_as_int() -
        rhs_syntax.num_ancestors().reinterpret_as_int())
        .abs()
        .reinterpret_as_uint() // TODO: unsigned_abs
      let probably_punctuation = lhs_syntax.looks_like_punctuation()

      // Both nodes are equal, the happy case.
      let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
        lhs_syntax.next_sibling(),
        rhs_syntax.next_sibling(),
        v.lhs_parent_id,
        v.rhs_parent_id,
        v.parents,
      )
      let vertex = allocate_if_new(
        Vertex::{
          neighbours: Ref::new(None),
          predecessor: Ref::new(None),
          lhs_syntax,
          rhs_syntax,
          parents,
          lhs_parent_id,
          rhs_parent_id,
        },
        seen,
      )
      neighbours.push(
        (UnchangedNode(depth_difference~, probably_punctuation~), vertex),
      )
    }
    if lhs_syntax
      is List(
        open_content=lhs_open_content,
        close_content=lhs_close_content,
        children=lhs_children,
        ..
      ) &&
      rhs_syntax
      is List(
        open_content=rhs_open_content,
        close_content=rhs_close_content,
        children=rhs_children,
        ..
      ) {
      // The list delimiters are equal, but children may not be.
      if lhs_open_content == rhs_open_content &&
        lhs_close_content == rhs_close_content {
        let lhs_next = lhs_children.get(0)
        let rhs_next = rhs_children.get(0)

        // TODO: be consistent between parents_next and next_parents.
        let parents_next = push_both_delimiters(
          v.parents,
          lhs_syntax,
          rhs_syntax,
        )
        let depth_difference = (lhs_syntax.num_ancestors().reinterpret_as_int() -
          rhs_syntax.num_ancestors().reinterpret_as_int())
          .abs()
          .reinterpret_as_uint()

        // When we enter a list, we may need to immediately
        // pop several levels if the list has no children.

        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          lhs_next,
          rhs_next,
          Some(lhs_syntax.id()),
          Some(rhs_syntax.id()),
          parents_next,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((EnterUnchangedDelimiter(depth_difference~), vertex))
      }
    }
    if lhs_syntax
      is Atom(content=lhs_content, kind=Comment | String(_) as lhs_kind, ..) &&
      rhs_syntax
      is Atom(content=rhs_content, kind=Comment | String(_) as rhs_kind, ..) {
      // Both sides are comments/both sides are strings and
      // their content is reasonably similar.
      if lhs_kind == rhs_kind && lhs_content != rhs_content {
        let levenshtein_pct = (normalized_levenshtein(
            lhs=lhs_content,
            rhs=rhs_content,
          ) *
          100.0)
          .round()
          .to_uint()
        let edge = if lhs_kind is Comment {
          Edge::ReplacedComment(levenshtein_pct~)
        } else {
          Edge::ReplacedString(levenshtein_pct~)
        }
        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          lhs_syntax.next_sibling(),
          rhs_syntax.next_sibling(),
          v.lhs_parent_id,
          v.rhs_parent_id,
          v.parents,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((edge, vertex))
      }
    }
  }
  if v.lhs_syntax is Some(lhs_syntax) {
    match lhs_syntax {
      // Step over this novel atom.
      Atom(..) => {
        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          lhs_syntax.next_sibling(),
          v.rhs_syntax,
          v.lhs_parent_id,
          v.rhs_parent_id,
          v.parents,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((NovelAtomLHS, vertex))
      }
      List(children~, ..) => {
        let lhs_next = children.get(0)
        let parents_next = push_lhs_delimiter(v.parents, lhs_syntax)
        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          lhs_next,
          v.rhs_syntax,
          Some(lhs_syntax.id()),
          v.rhs_parent_id,
          parents_next,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((EnterNovelDelimiterLHS, vertex))
      }
    }
  }
  if v.rhs_syntax is Some(rhs_syntax) {
    match rhs_syntax {
      // Step over this novel atom.
      Atom(..) => {
        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          v.lhs_syntax,
          rhs_syntax.next_sibling(),
          v.lhs_parent_id,
          v.rhs_parent_id,
          v.parents,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((NovelAtomRHS, vertex))
      }
      // Step into this partially/fully novel list.
      List(children~, ..) => {
        let rhs_next = children.get(0)
        let parents_next = push_rhs_delimiter(v.parents, rhs_syntax)
        let (lhs_syntax, rhs_syntax, lhs_parent_id, rhs_parent_id, parents) = pop_all_parents(
          v.lhs_syntax,
          rhs_next,
          v.lhs_parent_id,
          Some(rhs_syntax.id()),
          parents_next,
        )
        let vertex = allocate_if_new(
          Vertex::{
            neighbours: Ref::new(None),
            predecessor: Ref::new(None),
            lhs_syntax,
            rhs_syntax,
            parents,
            lhs_parent_id,
            rhs_parent_id,
          },
          seen,
        )
        neighbours.push((EnterNovelDelimiterRHS, vertex))
      }
    }
  }
  v.neighbours.val = Some(neighbours)
}

///|UUID(7b58d72b-9364-4b33-bb47-a42cf8bfbf45)
fn populate_change_map(
  route : Array[(Edge, Vertex)],
  change_map : ChangeMap,
) -> Unit {
  for ev in route {
    let (e, v) = ev
    match e {
      UnchangedNode(..) => {
        // No change on this node or its children.
        let lhs = v.lhs_syntax.unwrap()
        let rhs = v.rhs_syntax.unwrap()
        change_map.insert_deep_unchanged(node=lhs, opposite_node=rhs)
        change_map.insert_deep_unchanged(node=rhs, opposite_node=lhs)
      }
      EnterUnchangedDelimiter(..) => {
        // No change on the outer delimiter, but children may
        // have changed.
        let lhs = v.lhs_syntax.unwrap()
        let rhs = v.rhs_syntax.unwrap()
        change_map.insert(lhs, Unchanged(rhs))
        change_map.insert(rhs, Unchanged(lhs))
      }
      ReplacedComment(levenshtein_pct~) | ReplacedString(levenshtein_pct~) => {
        let lhs = v.lhs_syntax.unwrap()
        let rhs = v.rhs_syntax.unwrap()
        let change_kind = fn(first : Syntax, second : Syntax) {
          if e is ReplacedComment(..) {
            ChangeKind::ReplacedComment(lhs=first, rhs=second)
          } else {
            ChangeKind::ReplacedString(lhs=first, rhs=second)
          }
        }
        if levenshtein_pct > 20 {
          change_map.insert(lhs, change_kind(lhs, rhs))
          change_map.insert(rhs, change_kind(rhs, lhs))
        } else {
          change_map.insert(lhs, Novel)
          change_map.insert(rhs, Novel)
        }
      }
      NovelAtomLHS | EnterNovelDelimiterLHS => {
        let lhs = v.lhs_syntax.unwrap()
        change_map.insert(lhs, Novel)
      }
      NovelAtomRHS | EnterNovelDelimiterRHS => {
        let rhs = v.rhs_syntax.unwrap()
        change_map.insert(rhs, Novel)
      }
    }
  }
}
