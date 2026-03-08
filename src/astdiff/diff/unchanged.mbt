///|UUID(dd23a24f-6ac3-473f-9c51-0994f0b96dbc)
fn shared_prefix_len(lhs : ArrayView[Syntax], rhs : ArrayView[Syntax]) -> Int {
  let limit = @cmp.minimum(lhs.length(), rhs.length())
  let mut i = 0
  while i < limit && lhs[i].content_id() == rhs[i].content_id() {
    i += 1
  }
  i
}

///|UUID(2212714b-3c34-4afe-af87-5b11b360d248)
fn shared_suffix_len(
  lhs : ArrayView[Syntax],
  rhs : ArrayView[Syntax],
  prefix_len : Int,
) -> Int {
  let limit = @cmp.minimum(lhs.length(), rhs.length()) - prefix_len
  let mut i = 0
  while i < limit &&
        lhs[lhs.length() - i - 1].content_id() ==
        rhs[rhs.length() - i - 1].content_id() {
    i += 1
  }
  i
}

///|UUID(f93e27f9-6229-4341-9401-d6d3bb99b8d1)
fn can_mark_deep_unchanged(lhs : Syntax, rhs : Syntax) -> Bool {
  let lhs_content_id = lhs.content_id()
  lhs_content_id != 0 && lhs_content_id == rhs.content_id()
}

///|UUID(7ceca725-0cae-4179-8256-9980b4d5afbc)
fn same_root_content(lhs : Syntax, rhs : Syntax) -> Bool {
  let lhs_content_id = lhs.content_id()
  lhs_content_id != 0 && lhs_content_id == rhs.content_id()
}

///|UUID(7421325a-ce98-4d22-9c09-fcfeb5617292)
fn root_matches(
  lhs : ArrayView[Syntax],
  rhs : ArrayView[Syntax],
) -> Array[(Int, Int)] {
  let width = rhs.length() + 1
  let dp = Array::make((lhs.length() + 1) * width, 0)
  let index = fn(i : Int, j : Int) { i * width + j }

  let mut i = lhs.length()
  while i > 0 {
    i -= 1
    let mut j = rhs.length()
    while j > 0 {
      j -= 1
      dp[index(i, j)] = if same_root_content(lhs[i], rhs[j]) {
        dp[index(i + 1, j + 1)] + 1
      } else {
        @cmp.maximum(dp[index(i + 1, j)], dp[index(i, j + 1)])
      }
    }
  }

  let matches = Array::new()
  let mut lhs_i = 0
  let mut rhs_i = 0
  while lhs_i < lhs.length() && rhs_i < rhs.length() {
    if same_root_content(lhs[lhs_i], rhs[rhs_i]) {
      matches.push((lhs_i, rhs_i))
      lhs_i += 1
      rhs_i += 1
    } else if dp[index(lhs_i + 1, rhs_i)] >= dp[index(lhs_i, rhs_i + 1)] {
      lhs_i += 1
    } else {
      rhs_i += 1
    }
  }
  matches
}

///|UUID(582cc703-3136-47bf-8584-6493cc7e062e)
fn mark_root_segments(
  lhs_roots : ArrayView[Syntax],
  rhs_roots : ArrayView[Syntax],
  change_map : ChangeMap,
  graph_limit : UInt,
) -> Unit raise ExceededGraphLimit {
  match (lhs_roots.length(), rhs_roots.length()) {
    (0, 0) => ()
    (_, 0) =>
      for lhs in lhs_roots {
        change_map.insert_deep_novel(lhs)
      }
    (0, _) =>
      for rhs in rhs_roots {
        change_map.insert_deep_novel(rhs)
      }
    (1, 1) =>
      mark_syntax_subtree(
        Some(lhs_roots[0]),
        Some(rhs_roots[0]),
        change_map,
        graph_limit,
      )
    _ => {
      let matches = root_matches(lhs_roots, rhs_roots)
      if matches.is_empty() {
        let paired = @cmp.minimum(lhs_roots.length(), rhs_roots.length())
        for i in 0..<paired {
          mark_syntax_subtree(
            Some(lhs_roots[i]),
            Some(rhs_roots[i]),
            change_map,
            graph_limit,
          )
        }
        for i in paired..<lhs_roots.length() {
          change_map.insert_deep_novel(lhs_roots[i])
        }
        for i in paired..<rhs_roots.length() {
          change_map.insert_deep_novel(rhs_roots[i])
        }
        return
      }

      let mut lhs_start = 0
      let mut rhs_start = 0
      for match_ in matches {
        let (lhs_i, rhs_i) = match_
        mark_root_segments(
          lhs_roots[lhs_start:lhs_i],
          rhs_roots[rhs_start:rhs_i],
          change_map,
          graph_limit,
        )
        change_map.insert_deep_unchanged(
          node=lhs_roots[lhs_i],
          opposite_node=rhs_roots[rhs_i],
        )
        change_map.insert_deep_unchanged(
          node=rhs_roots[rhs_i],
          opposite_node=lhs_roots[lhs_i],
        )
        lhs_start = lhs_i + 1
        rhs_start = rhs_i + 1
      }
      mark_root_segments(
        lhs_roots[lhs_start:lhs_roots.length()],
        rhs_roots[rhs_start:rhs_roots.length()],
        change_map,
        graph_limit,
      )
    }
  }
}

///|UUID(da4a311c-c833-4751-88db-334628e48edb)
fn mark_syntax_subtree(
  lhs_root : Syntax?,
  rhs_root : Syntax?,
  change_map : ChangeMap,
  graph_limit : UInt,
) -> Unit raise ExceededGraphLimit {
  match (lhs_root, rhs_root) {
    (None, None) => ()
    (Some(lhs), None) => change_map.insert_deep_novel(lhs)
    (None, Some(rhs)) => change_map.insert_deep_novel(rhs)
    (Some(lhs), Some(rhs)) =>
      if can_mark_deep_unchanged(lhs, rhs) {
        change_map.insert_deep_unchanged(node=lhs, opposite_node=rhs)
        change_map.insert_deep_unchanged(node=rhs, opposite_node=lhs)
      } else {
        match (lhs, rhs) {
          (
            Syntax::List(
              open_content=lhs_open,
              close_content=lhs_close,
              children=lhs_children,
              ..
            ),
            Syntax::List(
              open_content=rhs_open,
              close_content=rhs_close,
              children=rhs_children,
              ..
            ),
          ) if lhs_open == rhs_open && lhs_close == rhs_close => {
            change_map.insert(lhs, Unchanged(rhs))
            change_map.insert(rhs, Unchanged(lhs))
            mark_syntax_roots(
              lhs_children, rhs_children, change_map, graph_limit,
            )
          }
          _ => mark_syntax(Some(lhs), Some(rhs), change_map, graph_limit)
        }
      }
  }
}

///|UUID(dc6a7582-0628-4439-9af2-199e79557cf1)
pub fn mark_syntax_roots(
  lhs_roots : ArrayView[Syntax],
  rhs_roots : ArrayView[Syntax],
  change_map : ChangeMap,
  graph_limit : UInt,
) -> Unit raise ExceededGraphLimit {
  let prefix_len = shared_prefix_len(lhs_roots, rhs_roots)
  for i in 0..<prefix_len {
    change_map.insert_deep_unchanged(
      node=lhs_roots[i],
      opposite_node=rhs_roots[i],
    )
    change_map.insert_deep_unchanged(
      node=rhs_roots[i],
      opposite_node=lhs_roots[i],
    )
  }

  let suffix_len = shared_suffix_len(lhs_roots, rhs_roots, prefix_len)
  let lhs_suffix_start = lhs_roots.length() - suffix_len
  let rhs_suffix_start = rhs_roots.length() - suffix_len
  for offset in 0..<suffix_len {
    let lhs = lhs_roots[lhs_suffix_start + offset]
    let rhs = rhs_roots[rhs_suffix_start + offset]
    change_map.insert_deep_unchanged(node=lhs, opposite_node=rhs)
    change_map.insert_deep_unchanged(node=rhs, opposite_node=lhs)
  }

  mark_root_segments(
    lhs_roots[prefix_len:lhs_suffix_start],
    rhs_roots[prefix_len:rhs_suffix_start],
    change_map,
    graph_limit,
  )
}
