///|
let impl_fuzzy_name_marker : String = "__MOONDIFF_DECLARATION_NAME__"

///|
// Final confidence is measured in permille. A candidate must retain at least
// 70% weighted confidence after syntax receives three times the name weight.
let impl_fuzzy_threshold : Int = 700

///|
priv struct ImplFuzzyDecl {
  name : String
  owner : String
  node : @cst.CstNode
}

///|
priv struct ImplFuzzyContent {
  counts : @hashmap.HashMap[UInt, Int]
  size : Int
}

///|
priv struct ImplFuzzyGap {
  previous : Int?
  next : Int?
} derive(Eq)

///|
fn first_name_token(node : @cst.CstNode) -> @cst.CstNode? {
  match node.kind {
    Syntax_Identifier | Syntax_Literal =>
      if node.source_span.0 < node.source_span.1 {
        Some(node)
      } else {
        None
      }
    _ => {
      for entry in node.children {
        let (_, child) = entry
        if first_name_token(child) is Some(found) {
          return Some(found)
        }
      }
      None
    }
  }
}

///|
fn fuzzy_decl_from_node(
  source : String,
  owner : String,
  node : @cst.CstNode,
) -> ImplFuzzyDecl? {
  first_name_token(node).bind(fn(name_node) {
    let name = cst_node_text(source, name_node)
    if name.is_empty() {
      None
    } else {
      Some({ name, owner, node: name_node })
    }
  })
}

///|
fn fuzzy_decl_from_child(
  source : String,
  item : @cst.CstNode,
  label : String,
  owner : String,
) -> ImplFuzzyDecl? {
  first_child_node(item, label).bind(fn(node) {
    fuzzy_decl_from_node(source, owner, node)
  })
}

///|
fn fuzzy_receiver_owner(source : String, item : @cst.CstNode) -> String? {
  labelled_span_text(source, item, "name").map(fn(receiver) {
    let prefix = if first_child_text(source, item, "op") == Some("&") {
      "&"
    } else {
      ""
    }
    "method:\{prefix}\{receiver}"
  })
}

///|
fn impl_fuzzy_decl(source : String, item : @cst.CstNode) -> ImplFuzzyDecl? {
  match item.kind {
    Impl_Function =>
      if first_child_node(item, "method") is Some(method_node) {
        fuzzy_receiver_owner(source, item).bind(fn(owner) {
          fuzzy_decl_from_node(source, owner, method_node)
        })
      } else {
        fuzzy_decl_from_child(source, item, "name", "function")
      }
    Impl_TypeAbstract
    | Impl_TypeAlias
    | Impl_RecordStruct
    | Impl_TupleStruct
    | Impl_EnumVariant
    | Impl_ExtensibleEnum
    | Impl_ExtendEnum
    | Impl_Suberror
    | Impl_SuberrorEnum => fuzzy_decl_from_child(source, item, "name", "type")
    Impl_Trait => fuzzy_decl_from_child(source, item, "name", "trait")
    Impl_Let | Impl_Const => {
      let owner = if item.kind is Impl_Let { "let" } else { "const" }
      if first_child_node(item, "name") is Some(name) {
        fuzzy_decl_from_node(source, owner, name)
      } else {
        first_child_node(item, "pattern").bind(fn(pattern) {
          if pattern.kind is Pattern_Var {
            fuzzy_decl_from_node(source, owner, pattern)
          } else {
            None
          }
        })
      }
    }
    Impl_Test => fuzzy_decl_from_child(source, item, "name", "test")
    Impl_ImplMethod | Impl_ImplRelation => {
      let receiver = child_text_or_empty(source, item, "type")
      let receiver_prefix = if first_child_text(source, item, "op") == Some("&") {
        "&"
      } else {
        ""
      }
      let trait_name = labelled_span_text(source, item, "name").unwrap_or("")
      first_child_node(item, "method").bind(fn(method_node) {
        fuzzy_decl_from_node(
          source,
          "impl:\{receiver_prefix}\{receiver}:\{trait_name}",
          method_node,
        )
      })
    }
    Impl_EnumView => {
      let view_name = labelled_span_text(source, item, "name").unwrap_or("")
      let receiver = child_text_or_empty(source, item, "type")
      first_child_node(item, "method").bind(fn(method_node) {
        fuzzy_decl_from_node(
          source,
          "view:\{receiver}:\{view_name}",
          method_node,
        )
      })
    }
    // These declarations do not expose one unambiguous declaration name.
    Impl_Import | Impl_Extend | Impl_Using => None
    _ => None
  }
}

///|
fn fuzzy_name_position_matches(
  positions : ArrayView[@span.SingleLineSpan],
  name_node : @cst.CstNode,
) -> Bool {
  positions.length() == 1 &&
  name_node.loc.start.lnum == name_node.loc.end.lnum &&
  positions[0].line == name_node.loc.start.lnum &&
  positions[0].start_col == name_node.loc.start.column() &&
  positions[0].end_col == name_node.loc.end.column()
}

///|
fn clone_impl_fuzzy_syntax(
  node : @syntax.Syntax,
  name_node : @cst.CstNode,
  replaced : Ref[Int],
) -> @syntax.Syntax {
  match node {
    Atom(position~, content~, kind~, ..) => {
      let content = if fuzzy_name_position_matches(position, name_node) {
        replaced.val += 1
        impl_fuzzy_name_marker
      } else {
        content
      }
      @syntax.Syntax::atom(
        content~,
        position=position.map(fn(pos) { pos }),
        kind~,
      )
    }
    List(
      kind~,
      open_position~,
      open_content~,
      children~,
      close_position~,
      close_content~,
      ..
    ) =>
      @syntax.Syntax::list(
        open_content~,
        open_position=open_position.map(fn(pos) { pos }),
        children=children.map(fn(child) {
          clone_impl_fuzzy_syntax(child, name_node, replaced)
        }),
        close_content~,
        close_position=close_position.map(fn(pos) { pos }),
        kind?,
      )
  }
}

///|
fn impl_fuzzy_info(
  source : String,
  item : @cst.CstNode,
  root : @syntax.Syntax,
) -> ImplFuzzyInfo? {
  impl_fuzzy_decl(source, item).bind(fn(decl) {
    let replaced = Ref(0)
    let fuzzy_root = clone_impl_fuzzy_syntax(root, decl.node, replaced)
    if replaced.val == 1 {
      Some({
        kind: item.kind,
        name: decl.name,
        owner: decl.owner,
        root: fuzzy_root,
      })
    } else {
      None
    }
  })
}

///|
fn collect_impl_fuzzy_content(
  node : @syntax.Syntax,
  counts : @hashmap.HashMap[UInt, Int],
) -> Int {
  match node {
    // A list content id recursively fingerprints its complete CST subtree.
    // Counting atoms again would overweight shared punctuation and identifiers,
    // making a split helper look like a rename merely because its tokens overlap.
    Atom(..) => 0
    List(children~, ..) => {
      let content_id = node.content_id()
      counts[content_id] = counts.get(content_id).unwrap_or(0) + 1
      let mut size = 1
      for child in children {
        size += collect_impl_fuzzy_content(child, counts)
      }
      size
    }
  }
}

///|
fn make_impl_fuzzy_content(root : @syntax.Syntax) -> ImplFuzzyContent {
  let counts : @hashmap.HashMap[UInt, Int] = HashMap([])
  let size = collect_impl_fuzzy_content(root, counts)
  { counts, size }
}

///|
fn impl_fuzzy_syntax_similarity(
  old : ImplFuzzyContent,
  new : ImplFuzzyContent,
) -> Int {
  let total = old.size + new.size
  if total == 0 {
    return 1000
  }
  let mut intersection = 0
  for content_id, old_count in old.counts {
    let new_count = new.counts.get(content_id).unwrap_or(0)
    intersection += @cmp.minimum(old_count, new_count)
  }
  2000 * intersection / total
}

///|
fn impl_fuzzy_levenshtein(
  lhs : ArrayView[Char],
  rhs : ArrayView[Char],
  budget : @computation.Budget?,
) -> Int raise @computation.LimitExceeded {
  if budget is Some(budget) {
    budget.charge_matrix(lhs.length() + 1, rhs.length() + 1, TopLevelAlignment)
  }
  let rows : Array[Array[Int]] = [
    Array::make(rhs.length() + 1, 0),
    Array::make(rhs.length() + 1, 0),
  ]
  for j in 0..<=rhs.length() {
    rows[0][j] = j
  }
  for i in 1..<=lhs.length() {
    rows[i & 1][0] = i
    for j in 1..<=rhs.length() {
      rows[i & 1][j] = if lhs[i - 1] == rhs[j - 1] {
        rows[(i - 1) & 1][j - 1]
      } else {
        1 +
        @cmp.minimum(
          @cmp.minimum(rows[(i - 1) & 1][j - 1], rows[(i - 1) & 1][j]),
          rows[i & 1][j - 1],
        )
      }
    }
  }
  rows[lhs.length() & 1][rhs.length()]
}

///|
fn impl_fuzzy_name_similarity(
  old_name : String,
  new_name : String,
  budget : @computation.Budget?,
) -> Int raise @computation.LimitExceeded {
  let old_chars = old_name.to_array()
  let new_chars = new_name.to_array()
  let max_length = @cmp.maximum(old_chars.length(), new_chars.length())
  if max_length == 0 {
    return 1000
  }
  let distance = impl_fuzzy_levenshtein(old_chars, new_chars, budget)
  1000 * (max_length - distance) / max_length
}

///|
fn impl_fuzzy_score(
  old_info : ImplFuzzyInfo,
  old_content : ImplFuzzyContent,
  new_info : ImplFuzzyInfo,
  new_content : ImplFuzzyContent,
  budget : @computation.Budget?,
) -> Int raise @computation.LimitExceeded {
  let syntax = impl_fuzzy_syntax_similarity(old_content, new_content)
  let name = impl_fuzzy_name_similarity(old_info.name, new_info.name, budget)
  // Keep the score integral and deterministic: (3 * syntax + name) / 4.
  (3 * syntax + name) / 4
}

///|
fn impl_fuzzy_gaps(
  length : Int,
  anchor_ids : @hashmap.HashMap[Int, Int],
) -> Array[ImplFuzzyGap] {
  let previous : Array[Int?] = Array::make(length, None)
  let next : Array[Int?] = Array::make(length, None)
  let mut current : Int? = None
  for i in 0..<length {
    if anchor_ids.get(i) is Some(anchor_id) {
      current = Some(anchor_id)
    } else {
      previous[i] = current
    }
  }
  current = None
  let mut i = length - 1
  while i >= 0 {
    if anchor_ids.get(i) is Some(anchor_id) {
      current = Some(anchor_id)
    } else {
      next[i] = current
    }
    i -= 1
  }
  Array::makei(length, fn(i) { { previous: previous[i], next: next[i] } })
}

///|
fn impl_fuzzy_uuid_conflicts(old : ImplUnit, new : ImplUnit) -> Bool {
  match (old.uuid, new.uuid) {
    (Some(old_uuid), Some(new_uuid)) => old_uuid != new_uuid
    _ => false
  }
}

///|
fn impl_fuzzy_candidate_score(
  old_index : Int,
  new_index : Int,
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_gaps : ArrayView[ImplFuzzyGap],
  new_gaps : ArrayView[ImplFuzzyGap],
  old_contents : ArrayView[ImplFuzzyContent?],
  new_contents : ArrayView[ImplFuzzyContent?],
  use_uuid : Bool,
  budget : @computation.Budget?,
) -> Int? raise @computation.LimitExceeded {
  if old_gaps[old_index] != new_gaps[new_index] ||
    (
      use_uuid &&
      impl_fuzzy_uuid_conflicts(old_units[old_index], new_units[new_index])
    ) {
    return None
  }
  match
    (
      old_units[old_index].fuzzy,
      old_contents[old_index],
      new_units[new_index].fuzzy,
      new_contents[new_index],
    ) {
    (Some(old_info), Some(old_content), Some(new_info), Some(new_content)) if old_info.kind ==
      new_info.kind &&
      old_info.owner == new_info.owner =>
      Some(
        impl_fuzzy_score(old_info, old_content, new_info, new_content, budget),
      )
    _ => None
  }
}

///|
fn align_fuzzy_impl_units(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  old_used : @hashmap.HashMap[Int, Bool],
  new_used : @hashmap.HashMap[Int, Bool],
  reliable : @hashmap.HashMap[Int, Int],
  use_uuid : Bool,
  budget : @computation.Budget?,
) -> Array[(Int, Int)] raise @computation.LimitExceeded {
  if reliable.is_empty() {
    return []
  }

  let old_anchor_ids : @hashmap.HashMap[Int, Int] = HashMap([])
  let new_anchor_ids : @hashmap.HashMap[Int, Int] = HashMap([])
  for old_index, new_index in reliable {
    old_anchor_ids[old_index] = old_index
    new_anchor_ids[new_index] = old_index
  }
  let old_gaps = impl_fuzzy_gaps(old_units.length(), old_anchor_ids)
  let new_gaps = impl_fuzzy_gaps(new_units.length(), new_anchor_ids)

  let old_roots : Array[@syntax.Syntax] = []
  let new_roots : Array[@syntax.Syntax] = []
  for i in 0..<old_units.length() {
    if !old_used.contains(i) && old_units[i].fuzzy is Some(info) {
      old_roots.push(info.root)
    }
  }
  for i in 0..<new_units.length() {
    if !new_used.contains(i) && new_units[i].fuzzy is Some(info) {
      new_roots.push(info.root)
    }
  }
  if old_roots.is_empty() || new_roots.is_empty() {
    return []
  }
  @syntax.init_all_info(old_roots, new_roots)

  let old_contents : Array[ImplFuzzyContent?] = Array::make(
    old_units.length(),
    None,
  )
  let new_contents : Array[ImplFuzzyContent?] = Array::make(
    new_units.length(),
    None,
  )
  for i in 0..<old_units.length() {
    if !old_used.contains(i) && old_units[i].fuzzy is Some(info) {
      old_contents[i] = Some(make_impl_fuzzy_content(info.root))
    }
  }
  for i in 0..<new_units.length() {
    if !new_used.contains(i) && new_units[i].fuzzy is Some(info) {
      new_contents[i] = Some(make_impl_fuzzy_content(info.root))
    }
  }

  let old_best = Array::make(old_units.length(), -1)
  let new_best = Array::make(new_units.length(), -1)
  for old_index in 0..<old_units.length() {
    if old_used.contains(old_index) {
      continue
    }
    let mut best_score = -1
    let mut best_index = -1
    let mut tied = false
    for new_index in 0..<new_units.length() {
      if !new_used.contains(new_index) &&
        impl_fuzzy_candidate_score(
          old_index, new_index, old_units, new_units, old_gaps, new_gaps, old_contents,
          new_contents, use_uuid, budget,
        )
        is Some(score) {
        if score > best_score {
          best_score = score
          best_index = new_index
          tied = false
        } else if score == best_score {
          tied = true
        }
      }
    }
    if best_score >= impl_fuzzy_threshold && !tied {
      old_best[old_index] = best_index
    }
  }

  for new_index in 0..<new_units.length() {
    if new_used.contains(new_index) {
      continue
    }
    let mut best_score = -1
    let mut best_index = -1
    let mut tied = false
    for old_index in 0..<old_units.length() {
      if !old_used.contains(old_index) &&
        impl_fuzzy_candidate_score(
          old_index, new_index, old_units, new_units, old_gaps, new_gaps, old_contents,
          new_contents, use_uuid, budget,
        )
        is Some(score) {
        if score > best_score {
          best_score = score
          best_index = old_index
          tied = false
        } else if score == best_score {
          tied = true
        }
      }
    }
    if best_score >= impl_fuzzy_threshold && !tied {
      new_best[new_index] = best_index
    }
  }

  let pairs = Array::new()
  for old_index in 0..<old_units.length() {
    let new_index = old_best[old_index]
    if new_index >= 0 && new_best[new_index] == old_index {
      pairs.push((old_index, new_index))
    }
  }
  pairs
}
