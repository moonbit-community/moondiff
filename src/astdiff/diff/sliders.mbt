///|UUID(89bda497-6076-4334-9b19-5ccb51ca46eb)
fn first_line_span(node : Syntax) -> SingleLineSpan? {
  match node {
    Syntax::Atom(position~, ..) => position.get(0)
    Syntax::List(open_position~, children~, close_position~, ..) => {
      if open_position.length() > 0 {
        return Some(open_position[0])
      }
      for child in children {
        match first_line_span(child) {
          Some(position) => return Some(position)
          None => ()
        }
      }
      close_position.get(0)
    }
  }
}

///|UUID(58b4e28c-85b6-4908-ab93-a9fa72735043)
fn last_line_span(node : Syntax) -> SingleLineSpan? {
  match node {
    Syntax::Atom(position~, ..) => position.last()
    Syntax::List(open_position~, children~, close_position~, ..) => {
      if close_position is [.., last] {
        return Some(last)
      }
      for child in children.rev_iter() {
        match last_line_span(child) {
          Some(position) => return Some(position)
          None => ()
        }
      }
      open_position.last()
    }
  }
}

///|UUID(66df5847-51b5-4dfe-892f-cf06d0b533b6)
fn distance_between(prev : Syntax, next : Syntax) -> Int {
  match (last_line_span(prev), first_line_span(next)) {
    (Some(prev_pos), Some(next_pos)) =>
      if prev_pos.line == next_pos.line {
        next_pos.start_col - prev_pos.end_col
      } else {
        (next_pos.line - prev_pos.line) * 10_000
      }
    _ => 0
  }
}

///|UUID(ac67c943-c495-4cb7-8a0a-02aeacceb1c7)
fn is_novel_deep(node : Syntax, change_map : ChangeMap) -> Bool {
  match node {
    Syntax::Atom(..) => change_map.get(node) is Some(Novel)
    Syntax::List(children~, ..) =>
      if !(change_map.get(node) is Some(Novel)) {
        false
      } else {
        children.all(fn(child) { is_novel_deep(child, change_map) })
      }
  }
}

///|UUID(4ff51d37-9ac2-405d-b2d5-db5a4748540b)
fn unchanged_descendants(
  nodes : ArrayView[Syntax],
  found : Array[Syntax],
  change_map : ChangeMap,
) -> Unit {
  if found.length() > 1 {
    return
  }
  for node in nodes {
    match change_map.get(node) {
      Some(Unchanged(_)) => found.push(node)
      Some(Novel) | Some(ReplacedComment(..) | ReplacedString(..)) =>
        match node {
          Syntax::List(children~, ..) =>
            unchanged_descendants(children, found, change_map)
          _ => ()
        }
      None => ()
    }
    if found.length() > 1 {
      return
    }
  }
}

///|UUID(fd27c1be-5ed7-47aa-997a-bf6596231434)
fn push_unchanged_to_ancestor(
  root : Syntax,
  inner : Syntax,
  change_map : ChangeMap,
) -> Unit {
  let inner_change = match change_map.get(inner) {
    Some(change) => change
    None => return
  }
  let delimiters_match = match (root, inner) {
    (
      Syntax::List(open_content=root_open, close_content=root_close, ..),
      Syntax::List(open_content=inner_open, close_content=inner_close, ..),
    ) => root_open == inner_open && root_close == inner_close
    _ => false
  }
  if delimiters_match {
    change_map.insert(root, inner_change)
    change_map.insert(inner, Novel)
  }
}

///|UUID(a1e5ec05-5fbd-4450-aaa6-c803930acb43)
fn push_unchanged_to_descendant(
  root : Syntax,
  inner : Syntax,
  change_map : ChangeMap,
) -> Unit {
  let root_change = match change_map.get(root) {
    Some(change) => change
    None => return
  }
  let delimiters_match = match (root, inner) {
    (
      Syntax::List(open_content=root_open, close_content=root_close, ..),
      Syntax::List(open_content=inner_open, close_content=inner_close, ..),
    ) => root_open == inner_open && root_close == inner_close
    _ => false
  }
  if delimiters_match {
    change_map.insert(root, Novel)
    change_map.insert(inner, root_change)
  }
}

///|UUID(56847a50-d9c8-4ada-b2cc-998fbc31a85c)
fn fix_nested_slider_prefer_inner(
  node : Syntax,
  change_map : ChangeMap,
) -> Unit {
  if node is Syntax::List(children~, ..) {
    match change_map.get(node) {
      Some(Novel) => {
        let found = Array::new()
        unchanged_descendants(children, found, change_map)
        if found is [candidate] && candidate is Syntax::List(..) {
          push_unchanged_to_ancestor(node, candidate, change_map)
        }
      }
      _ => ()
    }
    for child in children {
      fix_nested_slider_prefer_inner(child, change_map)
    }
  }
}

///|UUID(1759134c-a2f0-456c-9ea0-368a76d12462)
fn fix_nested_slider_prefer_outer(
  node : Syntax,
  change_map : ChangeMap,
) -> Unit {
  if node is Syntax::List(children~, ..) {
    match change_map.get(node) {
      Some(Unchanged(_)) => {
        let found = Array::new()
        unchanged_descendants(children, found, change_map)
        if found is [candidate] && candidate is Syntax::List(..) {
          push_unchanged_to_descendant(node, candidate, change_map)
        }
      }
      _ => ()
    }
    for child in children {
      fix_nested_slider_prefer_outer(child, change_map)
    }
  }
}

///|UUID(44bf2e2d-afe8-44f9-8ca4-0eaa5e9985e6)
fn novel_regions_after_unchanged(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
) -> Array[(Int, Int)] {
  let regions = Array::new()
  let mut region_start : Int? = None
  let mut region_end : Int? = None
  let mut after_unchanged = false
  for i, node in nodes.iter2() {
    match change_map.get(node) {
      Some(Unchanged(_)) => {
        if region_start is Some(start) {
          regions.push((start, region_end.unwrap()))
        }
        region_start = None
        region_end = None
        after_unchanged = true
      }
      Some(Novel) =>
        if after_unchanged || region_start is Some(_) {
          if region_start is None {
            region_start = Some(i)
          }
          region_end = Some(i)
        }
      Some(ReplacedComment(..) | ReplacedString(..)) | None => {
        if region_start is Some(start) {
          regions.push((start, region_end.unwrap()))
        }
        region_start = None
        region_end = None
        after_unchanged = false
      }
    }
  }
  if region_start is Some(start) {
    regions.push((start, region_end.unwrap()))
  }
  regions
}

///|UUID(f30b0264-f16c-4a62-afd8-2ea64a038b5e)
fn novel_regions_before_unchanged(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
) -> Array[(Int, Int)] {
  let regions = Array::new()
  let mut region_start : Int? = None
  let mut region_end : Int? = None
  for i, node in nodes.iter2() {
    match change_map.get(node) {
      Some(Unchanged(_)) => {
        if region_start is Some(start) {
          regions.push((start, region_end.unwrap()))
        }
        region_start = None
        region_end = None
      }
      Some(Novel) => {
        if region_start is None {
          region_start = Some(i)
        }
        region_end = Some(i)
      }
      Some(ReplacedComment(..) | ReplacedString(..)) | None => {
        region_start = None
        region_end = None
      }
    }
  }
  regions
}

///|UUID(58f626f8-1a3d-43d0-a83b-81b463ff2c9f)
fn slide_to_prev_node(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
  start_idx : Int,
  end_idx : Int,
) -> Unit {
  if start_idx == 0 || start_idx == end_idx {
    return
  }
  let start_node = nodes[start_idx]
  let last_node = nodes[end_idx]
  let before_start_node = nodes[start_idx - 1]
  let before_last_node = nodes[end_idx - 1]
  if before_start_node.content_id() != last_node.content_id() {
    return
  }
  if distance_between(before_start_node, start_node) >
    distance_between(before_last_node, last_node) {
    return
  }
  let opposite = match change_map.get(before_start_node) {
    Some(Unchanged(opposite)) =>
      if opposite.content_id() == before_start_node.content_id() {
        opposite
      } else {
        return
      }
    _ => return
  }
  let mut i = start_idx
  while i <= end_idx {
    if !is_novel_deep(nodes[i], change_map) {
      return
    }
    i += 1
  }
  change_map.insert_deep_novel(before_start_node)
  change_map.insert_deep_unchanged(node=last_node, opposite_node=opposite)
  change_map.insert_deep_unchanged(node=opposite, opposite_node=last_node)
}

///|UUID(cb5500a2-abf6-47f7-a5f3-3bc0297abb9c)
fn slide_to_next_node(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
  start_idx : Int,
  end_idx : Int,
) -> Unit {
  if end_idx + 1 >= nodes.length() || start_idx == end_idx {
    return
  }
  let start_node = nodes[start_idx]
  let last_node = nodes[end_idx]
  let after_start_node = nodes[start_idx + 1]
  let after_last_node = nodes[end_idx + 1]
  if after_last_node.content_id() != start_node.content_id() {
    return
  }
  if distance_between(last_node, after_last_node) >=
    distance_between(start_node, after_start_node) {
    return
  }
  let opposite = match change_map.get(after_last_node) {
    Some(Unchanged(opposite)) =>
      if opposite.content_id() == after_last_node.content_id() {
        opposite
      } else {
        return
      }
    _ => return
  }
  let mut i = start_idx
  while i <= end_idx {
    if !is_novel_deep(nodes[i], change_map) {
      return
    }
    i += 1
  }
  change_map.insert_deep_unchanged(node=start_node, opposite_node=opposite)
  change_map.insert_deep_unchanged(node=opposite, opposite_node=start_node)
  change_map.insert_deep_novel(after_last_node)
}

///|UUID(240191a1-55c5-4469-9f12-c2d1d11761de)
fn fix_sliders(nodes : ArrayView[Syntax], change_map : ChangeMap) -> Unit {
  for region in novel_regions_after_unchanged(nodes, change_map) {
    let (start_idx, end_idx) = region
    slide_to_prev_node(nodes, change_map, start_idx, end_idx)
  }
  for region in novel_regions_before_unchanged(nodes, change_map) {
    let (start_idx, end_idx) = region
    slide_to_next_node(nodes, change_map, start_idx, end_idx)
  }
}

///|UUID(110d4b45-5e67-4514-934d-b48245781c6d)
fn fix_all_sliders_one_step(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
) -> Unit {
  for node in nodes {
    if node is Syntax::List(children~, ..) {
      fix_all_sliders_one_step(children, change_map)
    }
  }
  fix_sliders(nodes, change_map)
}

///|UUID(5e76bab1-3d2d-4425-a787-48be88368f4a)
pub fn fix_all_sliders(
  nodes : ArrayView[Syntax],
  change_map : ChangeMap,
) -> Unit {
  fix_all_sliders_one_step(nodes, change_map)
  fix_all_sliders_one_step(nodes, change_map)
  for node in nodes {
    fix_nested_slider_prefer_inner(node, change_map)
    fix_nested_slider_prefer_outer(node, change_map)
  }
}
