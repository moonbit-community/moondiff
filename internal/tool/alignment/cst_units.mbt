///|
using @syntax {type MatchKind, type MatchedPos}

///|
// One normalized body trigram. Keeping the three tokens as an exact hash key
// avoids making extraction continuity depend on syntax-tree content ids.
priv struct ImplBodyTrigram {
  first : String
  second : String
  third : String
} derive(Eq, Hash)

///|
// Comment-free token trigrams for one function body. Mass counts duplicate
// trigrams as well as unique ones so coverage remains asymmetric.
priv struct ImplFuzzyBody {
  trigrams : @hashmap.HashMap[ImplBodyTrigram, Int]
  mass : Int
}

///|
// Shared source and CST references needed to build one body fingerprint.
// Keeping this input lightweight avoids allocating token/trigram collections
// for declarations that never reach the extraction challenge.
priv struct ImplFuzzyBodyInput {
  source : String
  node : @cst.CstNode
  declaration_name : String
}

///|
priv struct ImplTailDelegate {
  target : String
  through_self : Bool
}

///|
// Private metadata for the conservative rename and extraction passes. The
// syntax root is a deep copy whose declaration-name atom has been replaced by
// a fixed marker, so its content ids can be compared independently of the
// spelling change.
priv struct ImplFuzzyInfo {
  kind : @cst.NodeKind
  name : String
  owner : String
  root : @syntax.Syntax
  body_input : ImplFuzzyBodyInput?
  tail_delegate : ImplTailDelegate?
}

///|
// One top-level CST item plus any source-faithful leading trivia needed to
// render it independently. UUIDs, semantic keys, and unique root hashes let us
// align moved items before running the structural diff.
priv struct ImplUnit {
  root : @syntax.Syntax
  uuid : String?
  semantic_key : String?
  fuzzy : ImplFuzzyInfo?
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
// The exact character location occupied by a top-level test unit. The range
// starts at the first line-adjacent test-owned leading trivia node, so
// documentation comments, UUID markers, and `///|` separators are excluded
// together with the declaration while ordinary comments remain independent.
priv struct IgnoredTestRange {
  loc : @basic.Location
}

///|
// Successful CST collection keeps test ranges separately from elaborated
// implementation units. This ensures ignored tests never contribute syntax
// roots, top-level alignment work, graph size, or computation budget.
priv struct ImplCollection {
  units : Array[ImplUnit]
  ignored_tests : Array[IgnoredTestRange]
}

///|
// The top-level edit script produced after reliable and fuzzy pairing.
// Replacement means "diff these two roots"; delete/insert compare a real root
// with an empty side.
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
// MoonBit documentation comments and structural UUID/separator markers all
// use the own-line `///` family. Other comments remain visible unless the
// caller independently enables comment filtering.
fn test_owns_leading_trivia(source : String, node : @cst.CstNode) -> Bool {
  is_ownline_comment(node) && cst_node_text(source, node).has_prefix("///")
}

///|
// The parser keeps same-line trailing comments inside the test declaration's
// outer CST node. They begin after the body location and remain independently
// comparable even when the test syntax itself is excluded.
fn test_trailing_comments(
  item : @cst.CstNode,
  test_end : @basic.Position,
) -> Array[@cst.CstNode] {
  let comments : Array[@cst.CstNode] = []
  for entry in item.children {
    let (_, child) = entry
    if child.kind is Syntax_Comment && child.loc.start.cnum >= test_end.cnum {
      comments.push(child)
    }
  }
  comments
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
    fuzzy: item.bind(fn(item) { impl_fuzzy_info(source, item, root) }),
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
  let buf = StringBuilder()
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
fn collect_impl_units_detailed(
  source : String,
  root : @cst.CstNode,
  ignore_tests : Bool,
) -> ImplCollection {
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

  let retained_inputs : Array[ImplUnitInput] = []
  let ignored_tests : Array[IgnoredTestRange] = []
  for input in inputs {
    if ignore_tests && input.item is Some({ kind: Impl_Test, .. }) {
      let item = input.item.unwrap()
      let item_index = input.nodes.length() - 1
      let mut ignored_start = item_index
      let mut next_start_line = input.nodes[item_index].loc.start.lnum
      while ignored_start > 0 &&
            test_owns_leading_trivia(source, input.nodes[ignored_start - 1]) &&
            input.nodes[ignored_start - 1].loc.end.lnum + 1 == next_start_line {
        ignored_start -= 1
        next_start_line = input.nodes[ignored_start].loc.start.lnum
      }
      if ignored_start > 0 {
        retained_inputs.push(ImplUnitInput::{
          nodes: input.nodes[:ignored_start].to_owned(),
          item: None,
        })
      }
      let first = input.nodes[ignored_start]
      let test_end = first_child_node(item, "body")
        .map(body => body.loc.end)
        .unwrap_or(item.loc.end)
      ignored_tests.push({ loc: { start: first.loc.start, end: test_end } })
      let trailing = test_trailing_comments(item, test_end)
      if !trailing.is_empty() {
        retained_inputs.push({ nodes: trailing, item: None })
      }
    } else {
      retained_inputs.push(input)
    }
  }

  let node_groups = Array::new()
  for input in retained_inputs {
    node_groups.push(input.nodes)
  }
  let roots = @elab.elab_cst_node_groups(source, node_groups)
  let source_lines = @source_text.split_lines(source)
  let units = Array::new()
  for i in 0..<retained_inputs.length() {
    let input = retained_inputs[i]
    units.push(
      make_impl_unit(source, source_lines, input.nodes, input.item, roots[i]),
    )
  }
  { units, ignored_tests }
}
