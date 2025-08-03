///|
typealias UInt as SyntaxId // must non-zero

///|
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

///|
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

///|
pub impl Default for SyntaxInfo with default() {
  SyntaxInfo::new()
}

///|
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

///|
let default_syntax_atom : Syntax = Syntax::Atom(
  info=SyntaxInfo::default(),
  content="",
  position=[],
  kind=Normal,
)

///|
impl Default for Syntax with default() {
  // will be optimized by Syntax::list() constructor
  return default_syntax_atom
}

///|
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

///|
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

///|
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

///|
pub fn Syntax::atom(
  content~ : String,
  position~ : Array[SingleLineSpan],
  kind~ : AtomKind,
) -> Self {
  Syntax::Atom(info=SyntaxInfo::default(), position~, content~, kind~)
}

///|
pub fn Syntax::info(self : Self) -> SyntaxInfo {
  match self {
    Atom(info~, ..) => info
    List(info~, ..) => info
  }
}

///|
pub fn Syntax::parent(self : Self) -> Syntax? {
  self.info().parent
}

///|
pub fn Syntax::next_sibling(self : Self) -> Syntax? {
  self.info().next_sibling
}

///|
pub fn Syntax::id(self : Self) -> SyntaxId {
  self.info().unique_id
}

///|
pub fn Syntax::content_id(self : Self) -> UInt {
  self.info().content_id
}

///|
pub fn Syntax::content_is_unique(self : Self) -> Bool {
  self.info().content_is_unique
}

///|
pub fn Syntax::num_ancestors(self : Self) -> UInt {
  self.info().num_ancestors
}

///|
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

///|
pub enum StringKind {
  StringLiteral
  Text
}

///|
pub enum AtomKind {
  Normal
  String(StringKind)
  Type
  Comment
  Keyword
}
