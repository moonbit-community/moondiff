///|UUID(9ea4541d-91e0-4981-b8f4-c068d6994e52)
fn all_units_have_uuid(units : ArrayView[ImplUnit]) -> Bool {
  units.all(fn(unit) { unit.uuid is Some(_) })
}

///|
// Mutable occupancy for the fixed-order top-level alignment phases. Pairing is
// centralized so a later phase cannot overwrite an earlier replacement.
// Excluded new units remain unused and therefore still become final inserts.
priv struct AlignmentState {
  old_units : ArrayView[ImplUnit]
  new_units : ArrayView[ImplUnit]
  use_uuid : Bool
  old_used : @hashmap.HashMap[Int, Bool]
  new_used : @hashmap.HashMap[Int, Bool]
  replacements : @hashmap.HashMap[Int, Int]
  excluded_new : @hashmap.HashMap[Int, Bool]
}

///|
fn AlignmentState::new(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  use_uuid : Bool,
) -> Self {
  {
    old_units,
    new_units,
    use_uuid,
    old_used: @hashmap.HashMap([]),
    new_used: @hashmap.HashMap([]),
    replacements: @hashmap.HashMap([]),
    excluded_new: @hashmap.HashMap([]),
  }
}

///|
fn AlignmentState::pair(self : Self, old_index : Int, new_index : Int) -> Unit {
  if !self.old_used.contains(old_index) &&
    !self.new_used.contains(new_index) &&
    !self.excluded_new.contains(new_index) {
    self.old_used[old_index] = true
    self.new_used[new_index] = true
    self.replacements[old_index] = new_index
  }
}

///|
fn AlignmentState::exclude_new(self : Self, new_index : Int) -> Unit {
  self.excluded_new[new_index] = true
}

///|
fn AlignmentState::finish(self : Self) -> Array[ImplEdit] {
  let edits : Array[ImplEdit] = []
  for i in 0..<self.old_units.length() {
    if self.replacements.get(i) is Some(new_index) {
      edits.push(Replace(old=self.old_units[i], new=self.new_units[new_index]))
    } else {
      edits.push(Delete(self.old_units[i]))
    }
  }
  for i in 0..<self.new_units.length() {
    if !self.new_used.contains(i) {
      edits.push(Insert(self.new_units[i]))
    }
  }
  edits
}

///|
priv struct SemanticCandidateSet {
  pairs : Array[ImplSemanticPair]
  new_used : @hashmap.HashMap[Int, Bool]
}

///|
// Align duplicated UUIDs by occurrence order. This keeps repeated generated
// declarations deterministic without requiring UUIDs to be globally unique.
fn align_uuid_phase(state : AlignmentState) -> Unit {
  if !state.use_uuid {
    return
  }
  let new_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([])
  for i in 0..<state.new_units.length() {
    if state.new_units[i].uuid is Some(uuid) {
      new_positions.get_or_init(uuid, fn() { [] }).push(i)
    }
  }
  let new_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for i in 0..<state.old_units.length() {
    if state.old_units[i].uuid is Some(uuid) &&
      new_positions.get(uuid) is Some(indices) {
      let offset = new_offsets.get(uuid).unwrap_or(0)
      if offset < indices.length() {
        new_offsets[uuid] = offset + 1
        state.pair(i, indices[offset])
      }
    }
  }
}

///|UUID(75486f71-7af0-4c26-a905-97cdfbc7d623)
fn align_impl_units_by_uuid(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  if !all_units_have_uuid(old_units) || !all_units_have_uuid(new_units) {
    panic()
  }
  let state = AlignmentState::new(old_units, new_units, true)
  align_uuid_phase(state)
  state.finish()
}

///|
fn semantic_candidate_phase(state : AlignmentState) -> SemanticCandidateSet {
  let old_key_counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let new_key_counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for unit in state.old_units {
    if unit.semantic_key is Some(key) {
      old_key_counts[key] = old_key_counts.get(key).unwrap_or(0) + 1
    }
  }
  for unit in state.new_units {
    if unit.semantic_key is Some(key) {
      new_key_counts[key] = new_key_counts.get(key).unwrap_or(0) + 1
    }
  }

  // Keep non-UUID semantic matches provisional until the extraction
  // challenge has inspected every key occupant. Duplicate keys retain their
  // original occurrence-order pairing and are never contestable.
  let new_key_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<state.new_units.length() {
    if !state.new_used.contains(i) &&
      state.new_units[i].semantic_key is Some(key) {
      new_key_positions.get_or_init(key, fn() { [] }).push(i)
    }
  }
  let key_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let pairs : Array[ImplSemanticPair] = []
  let new_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  for i in 0..<state.old_units.length() {
    if !state.old_used.contains(i) &&
      state.old_units[i].semantic_key is Some(key) &&
      new_key_positions.get(key) is Some(indices) {
      let offset = key_offsets.get(key).unwrap_or(0)
      if offset < indices.length() {
        key_offsets[key] = offset + 1
        let new_index = indices[offset]
        pairs.push({
          old_index: i,
          new_index,
          unique_key: old_key_counts.get(key) == Some(1) &&
          new_key_counts.get(key) == Some(1),
        })
        new_used[new_index] = true
      }
    }
  }
  { pairs, new_used, }
}

///|
fn helper_extraction_phase(
  state : AlignmentState,
  candidates : SemanticCandidateSet,
  budget : @computation.ScopeBudget,
) -> Unit raise @computation.ScopeLimitExceeded {
  let new_challenge_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let old_body_cache : Array[ImplFuzzyBody?] = Array::make(
    state.old_units.length(),
    None,
  )
  let new_body_cache : Array[ImplFuzzyBody?] = Array::make(
    state.new_units.length(),
    None,
  )
  let old_competitors = impl_old_body_competitors_by_owner(state.old_units)
  for semantic_pair in candidates.pairs {
    if impl_semantic_challenge_helper(
        semantic_pair,
        state.old_units,
        state.new_units,
        old_body_cache,
        new_body_cache,
        old_competitors,
        state.use_uuid,
        state.new_used,
        candidates.new_used,
        new_challenge_used,
        budget,
      )
      is Some(helper_index) {
      new_challenge_used[helper_index] = true
      state.exclude_new(semantic_pair.new_index)
      state.pair(semantic_pair.old_index, helper_index)
    } else {
      state.pair(semantic_pair.old_index, semantic_pair.new_index)
    }
  }
}

///|
fn exact_content_phase(state : AlignmentState) -> Unit {
  let old_roots = impl_roots(state.old_units)
  let new_roots = impl_roots(state.new_units)
  @syntax.init_all_info(old_roots, new_roots)
  let old_content_counts : @hashmap.HashMap[UInt, Int] = @hashmap.HashMap([])
  for i in 0..<state.old_units.length() {
    if !state.old_used.contains(i) {
      let content_id = state.old_units[i].root.content_id()
      old_content_counts[content_id] = old_content_counts
        .get(content_id)
        .unwrap_or(0) +
        1
    }
  }
  let new_content_positions : @hashmap.HashMap[UInt, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<state.new_units.length() {
    if !state.new_used.contains(i) && !state.excluded_new.contains(i) {
      let content_id = state.new_units[i].root.content_id()
      new_content_positions.get_or_init(content_id, fn() { [] }).push(i)
    }
  }
  for i in 0..<state.old_units.length() {
    if !state.old_used.contains(i) {
      let content_id = state.old_units[i].root.content_id()
      if old_content_counts.get(content_id).unwrap_or(0) == 1 &&
        new_content_positions.get(content_id) is Some(indices) &&
        indices.length() == 1 {
        state.pair(i, indices[0])
      }
    }
  }
}

///|
fn fuzzy_phase(
  state : AlignmentState,
  budget : @computation.ScopeBudget,
) -> Unit raise @computation.ScopeLimitExceeded {
  // UUID, final semantic-key/challenge, and exact-content pairs are fixed
  // anchors. Displaced wrappers cannot re-enter through exact or fuzzy
  // matching. This deliberately prioritizes implementation-body continuity
  // and does not guarantee continuity for documentation attached to the
  // displaced wrapper; the final pass renders the whole wrapper as an insert.
  let fuzzy_pairs = align_fuzzy_impl_units(state, budget)
  for fuzzy_pair in fuzzy_pairs {
    let (old_index, new_index) = fuzzy_pair
    state.pair(old_index, new_index)
  }
}

///|UUID(218731b6-e35d-469a-b7a9-a31dcc3b1c70)
fn align_impl_units_by_key_impl(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
  budget : @computation.ScopeBudget,
  use_uuid? : Bool = true,
) -> Array[ImplEdit] raise @computation.ScopeLimitExceeded {
  let state = AlignmentState::new(old_units, new_units, use_uuid)
  align_uuid_phase(state)
  let candidates = semantic_candidate_phase(state)
  helper_extraction_phase(state, candidates, budget)
  exact_content_phase(state)
  fuzzy_phase(state, budget)
  state.finish()
}

///|UUID(efd8452b-7521-4f76-9171-86843cf72de6)
fn impl_roots(units : ArrayView[ImplUnit]) -> Array[@syntax.Syntax] {
  let roots = Array::new()
  for unit in units {
    roots.push(unit.root)
  }
  roots
}

///|
fn per_unit_plan(edits : Array[ImplEdit]) -> TopLevelPlan {
  let old_order : Array[Int] = []
  let new_order : Array[Int] = []
  for index, edit in edits {
    match edit {
      Replace(..) => {
        old_order.push(index)
        new_order.push(index)
      }
      Delete(_) => old_order.push(index)
      Insert(_) => new_order.push(index)
    }
  }
  old_order.sort_by_key(index => {
    match edits[index] {
      Replace(old~, ..) | Delete(old) => old.range.start
      Insert(_) => -1
    }
  })
  new_order.sort_by_key(index => {
    match edits[index] {
      Replace(new~, ..) | Insert(new) => new.range.start
      Delete(_) => -1
    }
  })
  let old_matched : Array[Int] = []
  for index in old_order {
    if edits[index] is Replace(..) {
      old_matched.push(index)
    }
  }
  let new_matched : Array[Int] = []
  for index in new_order {
    if edits[index] is Replace(..) {
      new_matched.push(index)
    }
  }
  PerUnit({
    edits,
    old_order,
    new_order,
    reordered: old_matched != new_matched,
  })
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
  budget : @computation.ScopeBudget,
  ignore_uuid? : Bool = false,
) -> TopLevelPlan raise @computation.ScopeLimitExceeded {
  if !ignore_uuid &&
    all_units_have_uuid(old_units) &&
    all_units_have_uuid(new_units) {
    per_unit_plan(align_impl_units_by_uuid(old_units, new_units))
  } else {
    let edits = align_impl_units_by_key_impl(
      old_units,
      new_units,
      budget,
      use_uuid=!ignore_uuid,
    )
    if impl_edits_have_replacement(edits) {
      per_unit_plan(edits)
    } else {
      RootList(old=old_units.to_owned(), new=new_units.to_owned())
    }
  }
}
