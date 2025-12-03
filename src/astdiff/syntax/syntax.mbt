///|UUID(a1293b4c-0874-4fc4-9902-e44b8cf7e8c8)
using @span {type SingleLineSpan}

///|UUID(36f67f34-7466-4f61-8b3d-4216a8be8dee)
pub type SyntaxId = UInt // must non-zero

///|UUID(d2ebef10-67f2-4bb6-ba40-9cb123ae7006)
pub struct SyntaxInfo {
  /// The previous node with the same parent as this one.
  mut previous_sibling : Syntax?
  /// The next node with the same parent as this one.
  mut next_sibling : Syntax?
  /// The syntax node that occurs before this one, in a depth-first
  /// tree traversal.
  mut prev : Syntax?
  /// The parent syntax node, if present.
  mut parent : Syntax?
  /// The number of nodes that are ancestors of this one.
  mut num_ancestors : UInt
  mut num_after : UInt64
  /// A number that uniquely identifies this syntax node.
  mut unique_id : SyntaxId
  /// A number that uniquely identifies the content of this syntax
  /// node. This may be the same as nodes on the other side of the
  /// diff, or nodes at different positions.
  ///
  /// Values are sequential, not hashes. Collisions never occur.
  mut content_id : UInt
  /// Is this the only node with this content? Ignores nodes on the
  /// other side.
  mut content_is_unique : Bool
}

///|UUID(2204ecdf-1b80-4a4d-b16d-f52f9c7f4a08)
pub fn SyntaxInfo::new() -> Self {
  SyntaxInfo::{
    previous_sibling: None,
    next_sibling: None,
    prev: None,
    parent: None,
    num_ancestors: 0,
    num_after: 0,
    unique_id: @uint.max_value,
    content_id: 0,
    content_is_unique: false,
  }
}

///|UUID(525b78cc-a805-4f38-9a3f-ac7213295ac4)
pub impl Default for SyntaxInfo with default() {
  SyntaxInfo::new()
}

///|UUID(f227a0b2-d44e-4afd-9d4b-ddbdb0f533d5)
pub enum Syntax {
  Atom(
    info~ : SyntaxInfo,
    position~ : Array[SingleLineSpan],
    content~ : String,
    kind~ : AtomKind
  )
  List(
    info~ : SyntaxInfo,
    open_position~ : Array[SingleLineSpan],
    open_content~ : String,
    children~ : Array[Syntax], // dont modify this
    close_position~ : Array[SingleLineSpan],
    close_content~ : String,
    // number of all subnodes
    num_descendants~ : UInt
  )
}

///|UUID(bec402de-e38b-45ca-9ae4-48b52e8ac3c7)
let default_syntax_atom : Syntax = Syntax::Atom(
  info=SyntaxInfo::default(),
  content="",
  position=[],
  kind=Normal,
)

///|UUID(7d58b16e-9242-4fa3-8465-80ac36208f17)
pub impl Eq for Syntax with equal(self, other) {
  self.info().content_id == other.info().content_id
}

///|UUID(1bc380e9-1250-41bf-8703-71257c729027)
pub impl Default for Syntax with default() {
  // will be optimized by Syntax::list() constructor
  return default_syntax_atom
}

///|UUID(c58acc73-ea64-47b3-99e9-b20192be0386)
pub impl @pp.Pretty for Syntax with pretty(syntax : Syntax) {
  match syntax {
    Atom(content~, ..) => @pp.text(content)
    List(children~, ..) => {
      let children = children.map(@pp.Pretty::pretty)
      @pp.group(
        @pp.text("(") +
        @pp.nest(indent=2, @pp.separate(@pp.line, children)) +
        @pp.char(')'),
      )
    }
  }
}

///|UUID(434529a4-abd1-4b42-aebc-b2312b92f78d)
pub fn Syntax::list(
  open_content~ : String,
  open_position~ : Array[SingleLineSpan],
  children~ : Array[Syntax],
  close_content~ : String,
  close_position~ : Array[SingleLineSpan],
) -> Self {
  // Skip empty atoms: they aren't displayed, so there's no
  // point making our syntax tree bigger. These occur when we're
  // parsing incomplete or malformed programs.
  let children = children.filter(fn(n) {
    match n {
      List(..) => true
      Atom(content~, ..) => not(content.is_empty())
    }
  })
  // Don't bother creating a list if we have no open/close and
  // there's only one child. 
  if children.length() == 1 &&
    open_content.is_empty() &&
    close_content.is_empty() {
    return children[0]
  }
  let mut num_descendants : UInt = 0
  for child in children {
    match child {
      List(..) as child => num_descendants += child.num_descendants + 1
      Atom(..) => num_descendants += 1
    }
  }
  Syntax::List(
    info=SyntaxInfo::default(),
    open_position~,
    open_content~,
    children~,
    close_content~,
    close_position~,
    num_descendants~,
  )
}

///|UUID(06de1333-a230-4628-a342-85e995108456)
pub fn Syntax::simple_list(
  open_position~ : Array[SingleLineSpan],
  children~ : Array[Syntax],
  close_position~ : Array[SingleLineSpan],
) -> Self {
  // This is a convenience function for creating lists without
  // open/close content.
  let open_content = ""
  let close_content = ""
  Syntax::list(
    open_content~,
    open_position~,
    children~,
    close_content~,
    close_position~,
  )
}

///|UUID(bfca4574-c7ee-49ba-856d-5ae9151f2ec8)
pub fn Syntax::atom(
  content~ : String,
  position~ : Array[SingleLineSpan],
  kind~ : AtomKind,
) -> Self {
  Syntax::Atom(info=SyntaxInfo::default(), position~, content~, kind~)
}

///|UUID(d98843b3-75e9-4a9a-8a4c-9f21308b9dca)
pub fn Syntax::info(self : Self) -> SyntaxInfo {
  match self {
    Atom(info~, ..) => info
    List(info~, ..) => info
  }
}

///|UUID(63faddb5-ec57-421e-8d80-2160c468f15a)
pub fn Syntax::parent(self : Self) -> Syntax? {
  self.info().parent
}

///|UUID(f4599ca6-61ca-4410-a414-792ba1f82156)
pub fn Syntax::next_sibling(self : Self) -> Syntax? {
  self.info().next_sibling
}

///|UUID(81d457d8-2c84-4076-b781-bf24684aac2b)
pub fn Syntax::id(self : Self) -> SyntaxId {
  self.info().unique_id
}

///|UUID(1c5505ee-407a-4d91-8da0-f0c51d55de76)
pub fn Syntax::content_id(self : Self) -> UInt {
  self.info().content_id
}

///|UUID(dfdebc9c-a7ff-4a48-bfd6-36120e4820dc)
pub fn Syntax::content_is_unique(self : Self) -> Bool {
  self.info().content_is_unique
}

///|UUID(bead19e5-664b-4f68-8928-0fe34ed94f36)
pub fn Syntax::num_ancestors(self : Self) -> UInt {
  self.info().num_ancestors
}

///|UUID(689e4a0f-bb8d-4bad-bcb0-d0f7bcea711e)
pub fn Syntax::comment_positions(
  nodes : ArrayView[Syntax],
) -> Array[SingleLineSpan] {
  fn walk_comment_positions(
    node : Syntax,
    positions : Array[SingleLineSpan],
  ) -> Unit {
    match node {
      Atom(position~, kind~, ..) =>
        if kind is Comment {
          positions.push_iter(position.iter())
        }
      List(children~, ..) =>
        for child in children {
          walk_comment_positions(child, positions)
        }
    }
  }

  let positions = Array::new(capacity=50)
  for node in nodes {
    walk_comment_positions(node, positions)
  } else {
    positions
  }
}

///|UUID(9e566b27-2a0c-4777-8ae0-07fdf04f1cff)
pub fn init_all_info(
  lhs_roots : ArrayView[Syntax],
  rhs_roots : ArrayView[Syntax],
) -> Unit {
  init_info(lhs_roots, rhs_roots)
  init_next_prev(lhs_roots)
  init_next_prev(rhs_roots)
}

///|UUID(0023a79f-ad16-4d6a-adba-e42e24133367)
fn init_next_prev(roots : ArrayView[Syntax]) -> Unit {
  set_prev_sibling(roots)
  set_next_sibling(roots)
  set_prev(roots, None)
}

///|UUID(d889d564-7c61-4814-bf6e-24597f71b6e8)
fn init_info(
  lhs_roots : ArrayView[Syntax],
  rhs_roots : ArrayView[Syntax],
) -> Unit {
  let id = Ref::new(1U)
  init_info_on_side(lhs_roots, id)
  init_info_on_side(rhs_roots, id)
  let existing = @hashmap.HashMap::new()
  set_content_id(lhs_roots, existing)
  set_content_id(rhs_roots, existing)
  set_content_is_unique(lhs_roots)
  set_content_is_unique(rhs_roots)
}

///|UUID(4e56af18-aa47-4efd-9a8d-fbff78528443)
type ContentId = UInt

///|UUID(4f54e639-9d2c-44a1-91f9-e57b5a57b9ba)
fn set_content_is_unique(nodes : ArrayView[Syntax]) -> Unit {
  let counts = @hashmap.HashMap::new()
  find_nodes_with_unique_content(nodes, counts)
  set_content_is_unique_from_counts(nodes, counts)
}

///|UUID(4a6b000f-7e11-4460-8a15-27ffa89c320e)
fn set_content_is_unique_from_counts(
  nodes : ArrayView[Syntax],
  counts : @hashmap.HashMap[ContentId, UInt64],
) -> Unit {
  for node in nodes {
    let count = counts.get(node.content_id()).unwrap_or_else(() => panic()) // "Count should be present"
    node.info().content_is_unique = count == 1
    if node is List(children~, ..) {
      set_content_is_unique_from_counts(children, counts)
    }
  }
}

///|UUID(4f5e8c3c-ddb9-45c2-89ae-4579cd8e5934)
fn find_nodes_with_unique_content(
  nodes : ArrayView[Syntax],
  counts : @hashmap.HashMap[ContentId, UInt64],
) -> Unit {
  for node in nodes {
    match counts.get(node.content_id()) {
      Some(count) => counts[node.content_id()] = count + 1
      None => counts.set(node.content_id(), 1)
    }
    if node is List(children~, ..) {
      find_nodes_with_unique_content(children, counts)
    }
  }
}

///|UUID(786c3580-5508-4015-af34-6476af74ce5a)
type ContentKey = (String?, String?, Array[UInt], Bool, Bool)

///|UUID(31918e2f-f46e-4be9-9922-71a56ffaa181)
fn set_content_id(
  nodes : ArrayView[Syntax],
  existing : @hashmap.HashMap[ContentKey, UInt],
) -> Unit {
  for node in nodes {
    let key = match node {
      Atom(content~, kind=highlight, ..) => {
        let is_comment = highlight == Comment
        let clean_content = if is_comment && content.split("\n").count() > 1 {
          content
          .split("\n")
          .map(l => l.trim_start(chars=" "))
          .collect()
          .join("\n")
        } else {
          content
        }
        (Some(clean_content), None, [], false, is_comment)
      }
      List(open_content~, close_content~, children~, ..) => {
        // Recurse first, so children all have their content_id set.
        set_content_id(children, existing)
        let children_content_ids = children
          .iterator()
          .map(c => c.info().content_id)
          .collect()
        (
          Some(open_content),
          Some(close_content),
          children_content_ids,
          true,
          true,
        )
      }
    }

    // Ensure the ID is always greater than zero, so we can
    // distinguish an uninitialised SyntaxInfo value.
    let next_id = existing.length().reinterpret_as_uint() + 1
    let content_id = existing.get_or_init(key, () => next_id)
    node.info().content_id = content_id
  }
}

///|UUID(052df6b4-380a-4f31-9675-a03d9695b370)
fn init_info_on_side(
  roots : ArrayView[Syntax],
  next_id : Ref[SyntaxId],
) -> Unit {
  set_parent(roots, None)
  set_num_ancestors(roots, 0)
  set_num_after(roots, 0)
  set_unique_id(roots, next_id)
}

///|UUID(7b3606f7-7e75-44dc-a774-1517a210a5e3)
fn set_unique_id(nodes : ArrayView[Syntax], next_id : Ref[SyntaxId]) -> Unit {
  for node in nodes {
    node.info().unique_id = next_id.val
    next_id.val = next_id.val + 1
  }
}

///|UUID(c3f65798-7051-4993-90cf-13d829f5cf48)
fn set_num_after(nodes : ArrayView[Syntax], parent_num_after : UInt64) -> Unit {
  for i, node in nodes.iterator2() {
    let num_after = parent_num_after +
      nodes.length().reinterpret_as_uint().to_uint64() -
      1 -
      i.reinterpret_as_uint().to_uint64()
    node.info().num_after = num_after
    if node is List(children~, ..) {
      set_num_after(children, num_after)
    }
  }
}

///|UUID(36b01c25-91f4-4317-8245-5cd485c46a16)
fn set_prev_sibling(nodes : ArrayView[Syntax]) -> Unit {
  let mut prev = None
  for node in nodes {
    node.info().previous_sibling = prev
    prev = Some(node)
    if node is List(children~, ..) {
      set_prev_sibling(children)
    }
  }
}

///|UUID(695f3c47-763c-46aa-8fae-3835ad929768)
fn set_next_sibling(nodes : ArrayView[Syntax]) -> Unit {
  for i, node in nodes.iterator2() {
    let sibling = if i + 1 < nodes.length() { Some(nodes[i + 1]) } else { None }
    node.info().next_sibling = sibling
    if node is List(children~, ..) {
      set_next_sibling(children)
    }
  }
}

///|UUID(bff9623e-0b73-4488-8406-02eb0e47bf91)
fn set_prev(nodes : ArrayView[Syntax], parent : Syntax?) -> Unit {
  for i, node in nodes.iterator2() {
    let node_prev = if i == 0 { parent } else { Some(nodes[i - 1]) }
    node.info().prev = node_prev
    if node is List(children~, ..) {
      set_prev(children, Some(node))
    }
  }
}

///|UUID(5ec8e3d9-1d14-4ff5-b122-f5217e1257ba)
fn set_parent(nodes : ArrayView[Syntax], parent : Syntax?) -> Unit {
  for node in nodes {
    node.info().parent = parent
    if node is List(children~, ..) {
      set_parent(children, Some(node))
    }
  }
}

///|UUID(250cf6fb-1fdc-4850-b78f-69873899d674)
fn set_num_ancestors(nodes : ArrayView[Syntax], num_ancestors : UInt) -> Unit {
  for node in nodes {
    node.info().num_ancestors = num_ancestors
    if node is List(children~, ..) {
      set_num_ancestors(children, num_ancestors + 1)
    }
  }
}

///|UUID(3d751dbd-a05e-46c7-aa9c-f7d1bfb5f5a9)
pub(all) enum StringKind {
  StringLiteral
  Text
} derive(Eq)

///|UUID(557e87f3-ee91-4143-9426-2a2cbaa54578)
pub(all) enum AtomKind {
  Normal
  String(StringKind)
  Type
  Comment
  Keyword
} derive(Eq)
