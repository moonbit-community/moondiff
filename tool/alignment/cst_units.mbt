///|
using @syntax {type MatchKind, type MatchedPos}

///|
// One top-level CST item plus any source-faithful leading trivia needed to
// render it independently. UUIDs, semantic keys, and unique root hashes let us
// align moved items before running the structural diff.
priv struct ImplUnit {
  root : @syntax.Syntax
  uuid : String?
  semantic_key : String?
  start_line : Int
  source : String
}

///|
// CST nodes are grouped first, then elaborated together with one file-level
// context. Keeping this intermediate form also lets source lines be indexed
// once before the final implementation units are built.
priv struct ImplUnitInput {
  nodes : Array[@cst.CstNode]
  item : @cst.CstNode?
}

///|
// The top-level edit script used when all units carry UUIDs. Replacement means
// "diff these two roots"; delete/insert compare a real root with an empty side.
priv enum ImplEdit {
  Replace(old~ : ImplUnit, new~ : ImplUnit)
  Delete(ImplUnit)
  Insert(ImplUnit)
}

///|
// The single top-level alignment decision shared by terminal rendering and
// renderer-neutral document calculation. Reliable UUID/key/hash matches are
// compared unit-by-unit; otherwise both engines compare the root lists/files
// as a whole.
priv enum TopLevelPlan {
  PerUnit(Array[ImplEdit])
  RootList(old~ : Array[ImplUnit], new~ : Array[ImplUnit])
}

///|
fn is_uuid_char(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '-'
}

///|
// UUID markers are source-level identity tags, not arbitrary UUID mentions in
// documentation. Match the complete raw comment spelling exactly.
fn parse_uuid_line(line : String) -> String? {
  let chars = line.to_array()
  if chars.length() < 11 {
    return None
  }
  let end_ = chars.length() - 1
  if chars[0] != '/' ||
    chars[1] != '/' ||
    chars[2] != '/' ||
    chars[3] != '|' ||
    chars[4] != 'U' ||
    chars[5] != 'U' ||
    chars[6] != 'I' ||
    chars[7] != 'D' ||
    chars[8] != '(' ||
    chars[end_] != ')' {
    return None
  }
  for i in 9..<end_ {
    if !is_uuid_char(chars[i]) {
      return None
    }
  }
  Some(String::from_array(chars[9:end_].to_owned()))
}

///|
fn is_ownline_comment(node : @cst.CstNode) -> Bool {
  match node.kind {
    Syntax_Comment => {
      for entry in node.children {
        let (label, child) = entry
        if label == Some("comment") && child.kind is Comment_Ownline {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn cst_node_text(source : String, node : @cst.CstNode) -> String {
  source[node.source_span.0:node.source_span.1].to_owned()
}

///|
fn nodes_uuid(source : String, nodes : ArrayView[@cst.CstNode]) -> String? {
  let mut uuid : String? = None
  for node in nodes {
    if node.kind.is_impl() {
      return uuid
    }
    if uuid is None &&
      is_ownline_comment(node) &&
      node.loc.start.cnum == node.loc.start.bol {
      uuid = parse_uuid_line(cst_node_text(source, node))
    }
  }
  None
}

///|
fn first_child_node(node : @cst.CstNode, wanted : String) -> @cst.CstNode? {
  for entry in node.children {
    let (label, child) = entry
    if label == Some(wanted) {
      return Some(child)
    }
  }
  None
}

///|
fn first_child_text(
  source : String,
  node : @cst.CstNode,
  wanted : String,
) -> String? {
  first_child_node(node, wanted).bind(fn(child) {
    let text = cst_node_text(source, child)
    if text.is_empty() {
      None
    } else {
      Some(text)
    }
  })
}

///|
fn labelled_span_text(
  source : String,
  node : @cst.CstNode,
  wanted : String,
) -> String? {
  let start = Ref(None)
  let mut end_ = 0
  for entry in node.children {
    let (label, child) = entry
    if label == Some(wanted) && !cst_node_text(source, child).is_empty() {
      if start.val is None {
        start.val = Some(child.source_span.0)
      }
      end_ = child.source_span.1
    }
  }
  start.val.map(fn(start) { source[start:end_].to_owned() })
}

///|
fn first_descendant_text(
  source : String,
  node : @cst.CstNode,
  wanted : String,
) -> String? {
  if first_child_text(source, node, wanted) is Some(text) {
    Some(text)
  } else {
    for entry in node.children {
      let (_, child) = entry
      if first_descendant_text(source, child, wanted) is Some(text) {
        return Some(text)
      }
    }
    None
  }
}

///|
fn child_text_or_empty(
  source : String,
  node : @cst.CstNode,
  label : String,
) -> String {
  first_child_text(source, node, label).unwrap_or("")
}

///|
fn impl_semantic_key(source : String, item : @cst.CstNode) -> String? {
  match item.kind {
    @cst.Impl_Import => {
      let kind = child_text_or_empty(source, item, "kind")
      Some("import:\{kind}")
    }
    @cst.Impl_Extend => {
      let type_name = child_text_or_empty(source, item, "type_name")
      let trait_name = child_text_or_empty(source, item, "trait")
      Some("extend:\{type_name}:\{trait_name}")
    }
    @cst.Impl_Function => {
      let name = labelled_span_text(source, item, "name")
      if first_child_text(source, item, "method") is Some(method_name) {
        let receiver_prefix = if first_child_text(source, item, "op") ==
          Some("&") {
          "&"
        } else {
          ""
        }
        name.map(fn(receiver) {
          "fn:\{receiver_prefix}\{receiver}::\{method_name}"
        })
      } else {
        name.map(fn(name) { "fn:::\{name}" })
      }
    }
    @cst.Impl_TypeAbstract
    | @cst.Impl_TypeAlias
    | @cst.Impl_RecordStruct
    | @cst.Impl_TupleStruct
    | @cst.Impl_EnumVariant
    | @cst.Impl_ExtensibleEnum
    | @cst.Impl_ExtendEnum
    | @cst.Impl_Suberror
    | @cst.Impl_SuberrorEnum =>
      first_child_text(source, item, "name").map(fn(name) { "type:\{name}" })
    @cst.Impl_Trait =>
      first_child_text(source, item, "name").map(fn(name) { "trait:\{name}" })
    @cst.Impl_Let => {
      let name = if first_child_text(source, item, "pattern") is Some(name) {
        Some(name)
      } else {
        first_child_text(source, item, "name")
      }
      name.map(fn(name) { "let:\{name}" })
    }
    @cst.Impl_Const => {
      let name = if first_child_text(source, item, "pattern") is Some(name) {
        Some(name)
      } else {
        first_child_text(source, item, "name")
      }
      name.map(fn(name) { "const:\{name}" })
    }
    @cst.Impl_Test =>
      first_child_text(source, item, "name").map(fn(name) { "test:\{name}" })
    @cst.Impl_ImplMethod | @cst.Impl_ImplRelation => {
      let trait_name = labelled_span_text(source, item, "name").unwrap_or("")
      let self_type = child_text_or_empty(source, item, "type")
      if first_child_text(source, item, "method") is Some(method_text) {
        let method_node = first_child_node(item, "method")
        let method_name = method_node
          .bind(fn(node) { first_descendant_text(source, node, "name") })
          .unwrap_or(method_text)
        Some("impl-fn:\{self_type}:\{trait_name}::\{method_name}")
      } else {
        Some("impl:\{self_type}:\{trait_name}")
      }
    }
    @cst.Impl_EnumView => {
      let name = labelled_span_text(source, item, "name").unwrap_or("")
      let method_name = child_text_or_empty(source, item, "method")
      Some("view:\{name}:\{method_name}")
    }
    @cst.Impl_Using => {
      let package_name = child_text_or_empty(source, item, "name")
      let body = child_text_or_empty(source, item, "body")
      Some("using:\{package_name}:\{body}")
    }
    _ => None
  }
}

///|
fn root_child_is_visible(source : String, node : @cst.CstNode) -> Bool {
  match node.kind {
    @cst.Syntax_Eof | @cst.Missing => false
    _ => !cst_node_text(source, node).is_empty()
  }
}

///|
fn make_impl_unit(
  source : String,
  source_lines : ArrayView[String],
  nodes : Array[@cst.CstNode],
  item : @cst.CstNode?,
  root : @syntax.Syntax,
) -> ImplUnit {
  let first = nodes[0]
  let last = nodes[nodes.length() - 1]
  ImplUnit::{
    root,
    uuid: nodes_uuid(source, nodes),
    semantic_key: item.bind(fn(item) { impl_semantic_key(source, item) }),
    start_line: first.loc.start.lnum,
    source: source_lines_slice(
      source_lines,
      first.loc.start.lnum,
      last.loc.end.lnum,
    ),
  }
}

///|
fn source_lines_slice(
  lines : ArrayView[String],
  start_line : Int,
  end_line : Int,
) -> String {
  if lines.is_empty() {
    return ""
  }
  let start = @cmp.maximum(start_line - 1, 0)
  let end_ = @cmp.minimum(end_line, lines.length())
  if start >= end_ {
    return ""
  }
  let buf = StringBuilder::new()
  for i in start..<end_ {
    if i > start {
      buf.write_char('\n')
    }
    buf.write_string(lines[i])
  }
  buf.to_string()
}

///|
// Root-level comments and separators precede the next declaration in the CST.
// Keep them with that declaration so documentation/UUID changes stay inside
// the same independently rendered unit. Trailing comment-only content becomes
// a final unit rather than disappearing from the structural diff.
fn collect_impl_units(source : String, root : @cst.CstNode) -> Array[ImplUnit] {
  let inputs = Array::new()
  let mut pending : Array[@cst.CstNode] = []
  for entry in root.children {
    let (label, child) = entry
    if label == Some("item") {
      let nodes = pending
      pending = []
      nodes.push(child)
      inputs.push(ImplUnitInput::{ nodes, item: Some(child) })
    } else if root_child_is_visible(source, child) {
      pending.push(child)
    }
  }
  if !pending.is_empty() {
    inputs.push(ImplUnitInput::{ nodes: pending, item: None })
  }

  let node_groups = Array::new()
  for input in inputs {
    node_groups.push(input.nodes)
  }
  let roots = @elab.elab_cst_node_groups(source, node_groups)
  let source_lines = @render.split_lines(source)
  let units = Array::new()
  for i in 0..<inputs.length() {
    let input = inputs[i]
    units.push(
      make_impl_unit(source, source_lines, input.nodes, input.item, roots[i]),
    )
  }
  units
}
