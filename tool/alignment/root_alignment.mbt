///|UUID(9ea4541d-91e0-4981-b8f4-c068d6994e52)
fn all_units_have_uuid(units : ArrayView[ImplUnit]) -> Bool {
  units.all(fn(unit) { unit.uuid is Some(_) })
}

///|UUID(75486f71-7af0-4c26-a905-97cdfbc7d623)
// Align duplicated UUIDs by occurrence order. This keeps repeated generated
// declarations deterministic without requiring UUIDs to be globally unique.
fn align_impl_units_by_uuid(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  let new_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([])
  for i in 0..<new_units.length() {
    if new_units[i].uuid is Some(uuid) {
      new_positions.get_or_init(uuid, fn() { [] }).push(i)
    } else {
      panic()
    }
  }

  let new_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let used_new : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let edits = Array::new()

  for old_unit in old_units {
    if old_unit.uuid is Some(uuid) {
      if new_positions.get(uuid) is Some(indices) {
        let offset = new_offsets.get(uuid).unwrap_or(0)
        if offset < indices.length() {
          let new_index = indices[offset]
          new_offsets[uuid] = offset + 1
          used_new.set(new_index, true)
          edits.push(Replace(old=old_unit, new=new_units[new_index]))
        } else {
          edits.push(Delete(old_unit))
        }
      } else {
        edits.push(Delete(old_unit))
      }
    } else {
      panic()
    }
  }

  for i in 0..<new_units.length() {
    if !used_new.contains(i) {
      edits.push(Insert(new_units[i]))
    }
  }
  edits
}

///|UUID(218731b6-e35d-469a-b7a9-a31dcc3b1c70)
fn align_impl_units_by_key_impl(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  budget : @computation.Budget?,
  use_uuid? : Bool = true,
) -> Array[ImplEdit] raise @computation.LimitExceeded {
  let old_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let new_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let replacements : @hashmap.HashMap[Int, Int] = @hashmap.HashMap([])

  fn pair(old_index : Int, new_index : Int) -> Unit {
    if !old_used.contains(old_index) && !new_used.contains(new_index) {
      old_used.set(old_index, true)
      new_used.set(new_index, true)
      replacements.set(old_index, new_index)
    }
  }

  if use_uuid {
    let new_uuid_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([],
    )
    for i in 0..<new_units.length() {
      if new_units[i].uuid is Some(uuid) {
        new_uuid_positions.get_or_init(uuid, fn() { [] }).push(i)
      }
    }
    let uuid_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
    for i in 0..<old_units.length() {
      if old_units[i].uuid is Some(uuid) {
        if new_uuid_positions.get(uuid) is Some(indices) {
          let offset = uuid_offsets.get(uuid).unwrap_or(0)
          if offset < indices.length() {
            uuid_offsets[uuid] = offset + 1
            pair(i, indices[offset])
          }
        }
      }
    }
  }

  let old_key_counts : @hashmap.HashMap[String, Int] = HashMap([])
  let new_key_counts : @hashmap.HashMap[String, Int] = HashMap([])
  for unit in old_units {
    if unit.semantic_key is Some(key) {
      old_key_counts[key] = old_key_counts.get(key).unwrap_or(0) + 1
    }
  }
  for unit in new_units {
    if unit.semantic_key is Some(key) {
      new_key_counts[key] = new_key_counts.get(key).unwrap_or(0) + 1
    }
  }

  // Keep non-UUID semantic matches provisional until the extraction
  // challenge has inspected every key occupant. Duplicate keys retain their
  // original occurrence-order pairing and are never contestable.
  let new_key_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<new_units.length() {
    if !new_used.contains(i) {
      if new_units[i].semantic_key is Some(key) {
        new_key_positions.get_or_init(key, fn() { [] }).push(i)
      }
    }
  }
  let key_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let semantic_pairs : Array[ImplSemanticPair] = []
  let new_semantic_used : @hashmap.HashMap[Int, Bool] = HashMap([])
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      if old_units[i].semantic_key is Some(key) {
        if new_key_positions.get(key) is Some(indices) {
          let offset = key_offsets.get(key).unwrap_or(0)
          if offset < indices.length() {
            key_offsets[key] = offset + 1
            let new_index = indices[offset]
            semantic_pairs.push({
              old_index: i,
              new_index,
              unique_key: old_key_counts.get(key) == Some(1) &&
              new_key_counts.get(key) == Some(1),
            })
            new_semantic_used[new_index] = true
          }
        }
      }
    }
  }

  let new_challenge_used : @hashmap.HashMap[Int, Bool] = HashMap([])
  let new_excluded_from_matching : @hashmap.HashMap[Int, Bool] = HashMap([])
  let old_body_cache : Array[ImplFuzzyBody?] = Array::make(
    old_units.length(),
    None,
  )
  let new_body_cache : Array[ImplFuzzyBody?] = Array::make(
    new_units.length(),
    None,
  )
  let old_competitors = impl_old_body_competitors_by_owner(old_units)
  for semantic_pair in semantic_pairs {
    if impl_semantic_challenge_helper(
        semantic_pair, old_units, new_units, old_body_cache, new_body_cache, old_competitors,
        use_uuid, new_used, new_semantic_used, new_challenge_used, budget,
      )
      is Some(helper_index) {
      new_challenge_used[helper_index] = true
      new_excluded_from_matching[semantic_pair.new_index] = true
      pair(semantic_pair.old_index, helper_index)
    } else {
      pair(semantic_pair.old_index, semantic_pair.new_index)
    }
  }

  let old_roots = impl_roots(old_units)
  let new_roots = impl_roots(new_units)
  @syntax.init_all_info(old_roots, new_roots)
  let old_content_counts : @hashmap.HashMap[UInt, Int] = @hashmap.HashMap([])
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      let content_id = old_units[i].root.content_id()
      old_content_counts[content_id] = old_content_counts
        .get(content_id)
        .unwrap_or(0) +
        1
    }
  }
  let new_content_positions : @hashmap.HashMap[UInt, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<new_units.length() {
    if !new_used.contains(i) && !new_excluded_from_matching.contains(i) {
      let content_id = new_units[i].root.content_id()
      new_content_positions.get_or_init(content_id, fn() { [] }).push(i)
    }
  }
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      let content_id = old_units[i].root.content_id()
      if old_content_counts.get(content_id).unwrap_or(0) == 1 {
        if new_content_positions.get(content_id) is Some(indices) &&
          indices.length() == 1 {
          pair(i, indices[0])
        }
      }
    }
  }

  // UUID, final semantic-key/challenge, and exact-content pairs are fixed
  // anchors. Displaced wrappers cannot re-enter through exact or fuzzy
  // matching. This deliberately prioritizes implementation-body continuity
  // and does not guarantee continuity for documentation attached to the
  // displaced wrapper; the final pass renders the whole wrapper as an insert.
  let fuzzy_pairs = align_fuzzy_impl_units(
    old_units, new_units, old_used, new_used, new_excluded_from_matching, replacements,
    use_uuid, budget,
  )
  for fuzzy_pair in fuzzy_pairs {
    let (old_index, new_index) = fuzzy_pair
    pair(old_index, new_index)
  }

  let edits = Array::new()
  for i in 0..<old_units.length() {
    if replacements.get(i) is Some(new_index) {
      edits.push(Replace(old=old_units[i], new=new_units[new_index]))
    } else {
      edits.push(Delete(old_units[i]))
    }
  }

  for i in 0..<new_units.length() {
    if !new_used.contains(i) {
      edits.push(Insert(new_units[i]))
    }
  }
  edits
}

///|UUID(efd8452b-7521-4f76-9171-86843cf72de6)
fn impl_line_base(unit : ImplUnit?) -> Int {
  if unit is Some(unit) {
    unit.start_line
  } else {
    1
  }
}

///|UUID(58ac384d-5e05-4e16-8ced-e465cedf4774)
fn impl_roots(units : ArrayView[ImplUnit]) -> Array[@syntax.Syntax] {
  let roots = Array::new()
  for unit in units {
    roots.push(unit.root)
  }
  roots
}

///|UUID(97bfcfe4-80de-498e-a147-90d250e6c93e)
fn impl_edits_have_replacement(edits : ArrayView[ImplEdit]) -> Bool {
  edits.any(fn(edit) {
    match edit {
      Replace(..) => true
      _ => false
    }
  })
}

///|
fn top_level_plan_impl(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  budget : @computation.Budget?,
  ignore_uuid? : Bool = false,
) -> TopLevelPlan raise @computation.LimitExceeded {
  if !ignore_uuid &&
    all_units_have_uuid(old_units) &&
    all_units_have_uuid(new_units) {
    PerUnit(align_impl_units_by_uuid(old_units, new_units))
  } else {
    let edits = align_impl_units_by_key_impl(
      old_units,
      new_units,
      budget,
      use_uuid=!ignore_uuid,
    )
    if impl_edits_have_replacement(edits) {
      PerUnit(edits)
    } else {
      RootList(old=old_units.to_owned(), new=new_units.to_owned())
    }
  }
}

///|
fn top_level_plan(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  ignore_uuid? : Bool = false,
) -> TopLevelPlan {
  let budget = @computation.Budget::new(@computation.default_limit())
  top_level_plan_impl(old_units, new_units, Some(budget), ignore_uuid~) catch {
    @computation.LimitExceeded(..) =>
      RootList(old=old_units.to_owned(), new=new_units.to_owned())
  }
}

///|
fn top_level_plan_with_budget(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  budget : @computation.Budget,
  ignore_uuid? : Bool = false,
) -> TopLevelPlan raise @computation.LimitExceeded {
  top_level_plan_impl(old_units, new_units, Some(budget), ignore_uuid~)
}
