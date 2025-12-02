///|UUID(a1293b4c-0874-4fc4-9902-e44b8cf7e8c8)
using @span {type SingleLineSpan}

///|UUID(36f67f34-7466-4f61-8b3d-4216a8be8dee)
pub type SyntaxId = UInt // must non-zero

///|UUID(d2ebef10-67f2-4bb6-ba40-9cb123ae7006)
pub struct SyntaxInfo {
  /// The previous node with the same parent as this one.
  previous_sibling : Syntax?
  /// The next node with the same parent as this one.
  next_sibling : Syntax?
  /// The syntax node that occurs before this one, in a depth-first
  /// tree traversal.
  prev : Syntax?
  /// The parent syntax node, if present.
  parent : Syntax?
  /// The number of nodes that are ancestors of this one.
  num_ancestors : UInt
  num_after : UInt64
  /// A number that uniquely identifies this syntax node.
  unique_id : SyntaxId
  /// A number that uniquely identifies the content of this syntax
  /// node. This may be the same as nodes on the other side of the
  /// diff, or nodes at different positions.
  ///
  /// Values are sequential, not hashes. Collisions never occur.
  content_id : UInt
  /// Is this the only node with this content? Ignores nodes on the
  /// other side.
  content_is_unique : Bool
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

///|UUID(3d751dbd-a05e-46c7-aa9c-f7d1bfb5f5a9)
pub(all) enum StringKind {
  StringLiteral
  Text
}

///|UUID(557e87f3-ee91-4143-9426-2a2cbaa54578)
pub(all) enum AtomKind {
  Normal
  String(StringKind)
  Type
  Comment
  Keyword
}
