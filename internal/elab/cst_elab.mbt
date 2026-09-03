///|
priv struct CstElabCtx {
  source : String
  line_widths : LineWidths
  line_ranges : Array[(Int, Int)]
}

///|
fn CstElabCtx::new(source : String) -> Self {
  let line_ranges = Array::new()
  line_ranges.push((0, 0))
  let mut line_start = 0
  let mut i = 0
  while i < source.length() {
    if source[i] == '\r' && i + 1 < source.length() && source[i + 1] == '\n' {
      line_ranges.push((line_start, i))
      i += 2
      line_start = i
    } else if source[i] == '\r' || source[i] == '\n' {
      line_ranges.push((line_start, i))
      i += 1
      line_start = i
    } else {
      i += 1
    }
  }
  line_ranges.push((line_start, source.length()))
  CstElabCtx::{
    source,
    line_widths: LineWidths::from_str(source),
    line_ranges,
  }
}

///|
fn node_has_type_atoms(kind : @cst.NodeKind) -> Bool {
  kind.is_type() ||
  (match kind {
    @cst.Name_Constructor
    | @cst.Name_Constr
    | @cst.Name_ConstrId
    | @cst.Expr_Constr
    | @cst.Pattern_Constr
    | @cst.Pattern_ConstrAny
    | @cst.Pattern_SpecialConstr => true
    _ => false
  })
}

///|
fn syntax_kind_is_token(kind : @cst.NodeKind) -> Bool {
  match kind {
    @cst.Syntax_Keyword
    | @cst.Syntax_Delimiter
    | @cst.Syntax_Separator
    | @cst.Syntax_Operator
    | @cst.Syntax_Identifier
    | @cst.Syntax_Label
    | @cst.Syntax_Accessor
    | @cst.Syntax_Literal
    | @cst.Syntax_Interpolation
    | @cst.Syntax_Attribute
    | @cst.Syntax_Comment
    | @cst.Syntax_Eof
    | @cst.Syntax_Unexpected => true
    _ => false
  }
}

///|
fn literal_atom_kind(node : @cst.CstNode) -> AtomKind {
  for entry in node.children {
    let (_, child) = entry
    match child.kind {
      @cst.Constant_Bool => return AtomKind::Keyword
      @cst.Constant_Byte
      | @cst.Constant_Bytes
      | @cst.Constant_Char
      | @cst.Constant_String
      | @cst.Constant_Regex =>
        return AtomKind::String(StringKind::StringLiteral)
      @cst.Constant_Int
      | @cst.Constant_Int64
      | @cst.Constant_UInt
      | @cst.Constant_UInt64
      | @cst.Constant_Float
      | @cst.Constant_Double
      | @cst.Constant_BigInt => return AtomKind::Normal
      _ => ()
    }
  }
  // Multiline string tokens carry only a scalar payload in the new CST.
  AtomKind::String(StringKind::StringLiteral)
}

///|
fn starts_with_uppercase_name(content : String) -> Bool {
  let mut i = 0
  if i < content.length() && content[i] == '.' {
    i += 1
  }
  i < content.length() && content[i] >= 'A' && content[i] <= 'Z'
}

///|
fn syntax_atom_kind(
  node : @cst.CstNode,
  content : String,
  type_context : Bool,
) -> AtomKind {
  match node.kind {
    @cst.Syntax_Comment => AtomKind::Comment
    @cst.Syntax_Keyword => AtomKind::Keyword
    @cst.Syntax_Operator if content == "readonly" ||
      content == "extend" ||
      content == "→" => AtomKind::Keyword
    @cst.Syntax_Interpolation => AtomKind::String(StringKind::StringLiteral)
    @cst.Syntax_Literal => literal_atom_kind(node)
    @cst.Syntax_Identifier | @cst.Syntax_Accessor if starts_with_uppercase_name(
        content,
      ) ||
      (type_context && content.length() > 0 && content[0] == '@') =>
      AtomKind::Type
    _ => AtomKind::Normal
  }
}

///|
fn first_child_with_label(
  children : ReadOnlyArray[(String?, @cst.CstNode)],
  wanted : String,
) -> Int? {
  for i in 0..<children.length() {
    let (label, _) = children[i]
    if label == Some(wanted) {
      return Some(i)
    }
  }
  None
}

///|
fn last_child_with_label(
  children : ReadOnlyArray[(String?, @cst.CstNode)],
  wanted : String,
) -> Int? {
  let mut i = children.length() - 1
  while i >= 0 {
    let (label, _) = children[i]
    if label == Some(wanted) {
      return Some(i)
    }
    i -= 1
  }
  None
}

///|
fn should_skip_child(label : String?) -> Bool {
  // Interpolation nodes also expose parsed segments that overlap the full
  // literal token. Moondiff treats a literal as one replaceable string atom,
  // so retaining both would duplicate source ranges in the diff tree.
  label == Some("segment")
}

///|
fn is_gap_whitespace(ch : UInt16) -> Bool {
  match ch {
    '\u{0009}'..='\u{000d}'
    | '\u{0020}'
    | '\u{00a0}'
    | '\u{1680}'
    | '\u{2000}'..='\u{200a}'
    | '\u{202f}'
    | '\u{205f}'
    | '\u{3000}'
    | '\u{feff}' => true
    _ => false
  }
}

///|
fn is_gap_word_char(ch : UInt16) -> Bool {
  match ch {
    '_' | '0'..='9' | 'a'..='z' | 'A'..='Z' => true
    _ => false
  }
}

///|
fn CstElabCtx::find_line(self : Self, offset : Int) -> Int {
  let mut low = 1
  let mut high = self.line_ranges.length() - 1
  let eof_line = high
  while low <= high {
    let mid = low + (high - low) / 2
    let (start, end_) = self.line_ranges[mid]
    if offset < start {
      high = mid - 1
    } else if offset > end_ {
      low = mid + 1
    } else {
      return mid
    }
  }
  eof_line
}

///|
fn CstElabCtx::gap_position(
  self : Self,
  start : Int,
  end_ : Int,
) -> SingleLineSpan {
  let line = self.find_line(start)
  let (line_start, _) = self.line_ranges[line]
  let start_col = self.source[line_start:start].to_owned().to_array().length() +
    1
  let end_col = self.source[line_start:end_].to_owned().to_array().length() + 1
  SingleLineSpan::{ line, start_col, end_col, }
}

///|
fn CstElabCtx::append_gap(
  self : Self,
  children : Array[Syntax],
  start_offset : Int,
  end_offset : Int,
) -> Unit {
  let mut i = start_offset
  while i < end_offset {
    if is_gap_whitespace(self.source[i]) {
      i += 1
      continue
    }
    let start = i
    let is_word = is_gap_word_char(self.source[i])
    i += 1
    while i < end_offset &&
          !is_gap_whitespace(self.source[i]) &&
          is_gap_word_char(self.source[i]) == is_word {
      i += 1
    }
    let content = self.source[start:i].to_owned()
    children.push(
      Syntax::atom(
        content~,
        position=[self.gap_position(start, i)],
        kind=AtomKind::Normal,
      ),
    )
  }
}

///|
fn CstElabCtx::node_text(self : Self, node : @cst.CstNode) -> String {
  self.source[node.source_span.0:node.source_span.1].to_owned()
}

///|
fn CstElabCtx::node_positions(
  self : Self,
  node : @cst.CstNode,
) -> Array[SingleLineSpan] {
  self.line_widths.loc_to_spans(node.loc)
}

///|
fn CstElabCtx::delimiter(
  self : Self,
  node : @cst.CstNode,
) -> (String, Array[SingleLineSpan]) {
  let content = self.node_text(node)
  if content.is_empty() {
    ("", [])
  } else {
    (content, self.node_positions(node))
  }
}

///|
fn CstElabCtx::elab_syntax_token(
  self : Self,
  node : @cst.CstNode,
  type_context : Bool,
) -> Syntax? {
  if node.kind is @cst.Syntax_Eof {
    return None
  }
  let content = self.node_text(node)
  if content.is_empty() {
    None
  } else {
    Some(
      Syntax::atom(
        content~,
        position=self.node_positions(node),
        kind=syntax_atom_kind(node, content, type_context),
      ),
    )
  }
}

///|
fn CstElabCtx::elab_node(
  self : Self,
  node : @cst.CstNode,
  inherited_type_context : Bool,
) -> Syntax? {
  if syntax_kind_is_token(node.kind) {
    return self.elab_syntax_token(node, inherited_type_context)
  }
  match node.kind {
    @cst.Missing | @cst.Leaf(_) => None
    kind => {
      let type_context = inherited_type_context || node_has_type_atoms(kind)
      let open_index = first_child_with_label(node.children, "open")
      let close_index = last_child_with_label(node.children, "close")
      let children = Array::new()
      let mut cursor = node.source_span.0
      for i in 0..<node.children.length() {
        let (label, child) = node.children[i]
        if should_skip_child(label) {
          continue
        }
        // The new CST appends semantic payload and location nodes after the
        // source-faithful children. Their spans overlap syntax already emitted.
        if child.source_span.0 < cursor {
          continue
        }
        if child.source_span.0 > cursor {
          self.append_gap(children, cursor, child.source_span.0)
        }
        if Some(i) != open_index && Some(i) != close_index {
          if self.elab_node(child, type_context) is Some(child) {
            children.push(child)
          }
        }
        if child.source_span.1 > cursor {
          cursor = child.source_span.1
        }
      }
      if node.source_span.1 > cursor {
        self.append_gap(children, cursor, node.source_span.1)
      }
      let (open_content, open_position) = if open_index is Some(i) {
        self.delimiter(node.children[i].1)
      } else {
        ("", [])
      }
      let (close_content, close_position) = if close_index is Some(i) {
        self.delimiter(node.children[i].1)
      } else {
        ("", [])
      }
      if children.is_empty() &&
        open_content.is_empty() &&
        close_content.is_empty() {
        None
      } else {
        Some(
          Syntax::list(
            open_content~,
            open_position~,
            children~,
            close_content~,
            close_position~,
            kind=ListKind::from_node_kind(kind),
          ),
        )
      }
    }
  }
}

///|
fn CstElabCtx::elab_nodes(
  self : Self,
  nodes : ArrayView[@cst.CstNode],
) -> Syntax {
  let children = Array::new()
  for node in nodes {
    if self.elab_node(node, false) is Some(node) {
      children.push(node)
    }
  }
  Syntax::simple_list(open_position=[], children~, close_position=[])
}

///|
/// Converts one source-faithful parser CST node into moondiff's matching tree.
/// Token text and positions are always sliced from the same original source
/// that was passed to `@cst.parse_structure` or `@cst.parse_expression`.
pub fn elab_cst(source : String, node : @cst.CstNode) -> Syntax {
  let ctx = CstElabCtx::new(source)
  ctx
  .elab_node(node, false)
  .unwrap_or_else(fn() {
    Syntax::simple_list(open_position=[], children=[], close_position=[])
  })
}

///|
/// Converts adjacent CST nodes into a single matching root while retaining
/// each node as a sibling. This is used to attach leading comments to a
/// top-level declaration without flattening its grammar shape.
pub fn elab_cst_nodes(
  source : String,
  nodes : ArrayView[@cst.CstNode],
) -> Syntax {
  CstElabCtx::new(source).elab_nodes(nodes)
}

///|
/// Converts several groups of adjacent CST nodes using one source index.
/// Top-level alignment uses this entry point so elaborating many declarations
/// scans the source once instead of once per declaration.
pub fn elab_cst_node_groups(
  source : String,
  groups : ArrayView[Array[@cst.CstNode]],
) -> Array[Syntax] {
  let ctx = CstElabCtx::new(source)
  let roots = Array::new()
  for nodes in groups {
    roots.push(ctx.elab_nodes(nodes))
  }
  roots
}
