///|UUID(9e00411e-058e-4cef-92e3-1a0637d1a928)
// Align every source line monotonically from matched syntax positions.
using @syntax {type MatchedPos}

///|UUID(43ea7bcf-0a8b-449e-aac4-dc8c0b633959)
pub type LineSet = @hashmap.HashMap[Int, Bool]

///|UUID(9675cda4-4b44-406d-9128-9d311f3dd4e7)
type OppositeMap = @hashmap.HashMap[Int, Array[Int]]

///|UUID(063b1c16-81dc-4dd7-a575-84b383f4f363)
fn flip_line_pair(pair : (Int?, Int?)) -> (Int?, Int?) {
  (pair.1, pair.0)
}

///|UUID(3ac03240-83ed-41c1-a6b0-45887515ff26)
fn flip_line_pairs(pairs : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let flipped = Array::new(capacity=pairs.length())
  for pair in pairs {
    flipped.push(flip_line_pair(pair))
  }
  flipped
}

///|UUID(3a91091f-c3dd-45d6-b53f-68cbe34048d0)
fn reversed_pairs(pairs : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let reversed = Array::new(capacity=pairs.length())
  let mut i = pairs.length()
  while i > 0 {
    i -= 1
    reversed.push(pairs[i])
  }
  reversed
}

///|UUID(edba51f3-f0ee-465a-8def-675360902dd6)
fn push_line(line_set : LineSet, line : Int) -> Unit {
  line_set.set(line, true)
}

///|UUID(6dea4ff2-3924-4405-a4b9-2d2b915eb63d)
fn add_opposite_line(
  opposites : OppositeMap,
  line : Int,
  opposite_line : Int,
) -> Unit {
  if line < 0 || opposite_line < 0 {
    return
  }
  let lines = opposites.get_or_init(line, fn() { [] })
  if !lines.contains(opposite_line) {
    lines.push(opposite_line)
    lines.sort()
  }
}

///|UUID(1bbf5231-2b70-4e32-8fdf-dff28a419898)
// Map each line on this side to the lines that contain matching unchanged
// positions on the opposite side.
fn opposite_positions(mps : ArrayView[MatchedPos]) -> OppositeMap {
  let opposites = @hashmap.HashMap([])
  for mp in mps {
    match mp.kind {
      Unchanged(opposite_pos~) => {
        let self_line = @syntax.line_index(mp.pos)
        for opposite in opposite_pos {
          add_opposite_line(opposites, self_line, @syntax.line_index(opposite))
        }
      }
      Novel => ()
    }
  } nobreak {
    opposites
  }
}

///|UUID(1be4c24f-d501-4268-a7fc-4cc39f737bcf)
// Collect line numbers containing novel positions on either side.
pub fn novel_line_sets(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> (LineSet, LineSet) {
  let lhs_lines = @hashmap.HashMap([])
  let rhs_lines = @hashmap.HashMap([])
  for mp in lhs_mps {
    if mp.kind.is_novel() {
      push_line(lhs_lines, @syntax.line_index(mp.pos))
    }
  }
  for mp in rhs_mps {
    if mp.kind.is_novel() {
      push_line(rhs_lines, @syntax.line_index(mp.pos))
    }
  }
  (lhs_lines, rhs_lines)
}

///|UUID(67f1ba22-01fd-49b9-884e-b047dd93fe23)
fn all_lines(mps : ArrayView[MatchedPos]) -> Array[Int] {
  let seen = @hashmap.HashMap([])
  for mp in mps {
    let line = @syntax.line_index(mp.pos)
    if line >= 0 {
      seen.set(line, true)
    }
  }
  let lines = Array::new(capacity=seen.length())
  for line, _ in seen {
    lines.push(line)
  }
  lines.sort()
  lines
}

///|UUID(744fbb0e-b4ab-4202-a020-f3b52d12dad5)
fn next_line_after(lines : ArrayView[Int], prev_line : Int?) -> Int? {
  for line in lines {
    if prev_line is Some(prev) {
      if line > prev {
        return Some(line)
      }
    } else {
      return Some(line)
    }
  }
  None
}

///|UUID(2d7570d2-4269-42f1-8097-58250d0336e5)
// Build an increasing list of line pairs from unchanged positions. Ambiguous
// many-to-many line matches are skipped so they do not force bad alignment.
fn matched_lines_from_unchanged(
  mps : ArrayView[MatchedPos],
) -> Array[(Int?, Int?)] {
  let line_to_opposites = opposite_positions(mps)
  let opposite_to_lines = @hashmap.HashMap([])
  for self_line, opposite_lines in line_to_opposites {
    for opposite_line in opposite_lines {
      add_opposite_line(opposite_to_lines, opposite_line, self_line)
    }
  }

  let highest_line = Ref(None)
  let highest_opposite_line = Ref(None)
  let matched = Array::new()
  for mp in mps {
    let self_line = @syntax.line_index(mp.pos)
    if self_line < 0 {
      continue
    }
    let opposite_line = if line_to_opposites.get(self_line)
      is Some(opposite_lines) {
      let candidate = next_line_after(opposite_lines, highest_opposite_line.val)
      if candidate is Some(candidate_line) {
        let reverse_is_unique = if opposite_to_lines.get(candidate_line)
          is Some(self_lines) {
          self_lines.length() == 1 && self_lines[0] == self_line
        } else {
          false
        }
        if opposite_lines.length() == 1 && reverse_is_unique {
          Some(candidate_line)
        } else {
          None
        }
      } else {
        None
      }
    } else {
      None
    }
    guard opposite_line is Some(opposite_line) else { continue }

    let should_insert = if highest_line.val is Some(highest) {
      self_line > highest
    } else {
      true
    }
    if should_insert {
      matched.push((Some(self_line), Some(opposite_line)))
      highest_line.val = Some(self_line)
      highest_opposite_line.val = Some(opposite_line)
    }
  }
  matched
}

///|UUID(647bcb7d-9201-4b6d-aee2-164fc21411ef)
// Insert lines from the opposite side that were not anchored by unchanged
// matches, preserving order around the existing pairs.
fn merge_in_opposite_lines(
  matched_lines : ArrayView[(Int?, Int?)],
  novel_opposite_lines : ArrayView[Int],
) -> Array[(Int?, Int?)] {
  let merged = Array::new()
  let mut i = 0
  for pair in matched_lines {
    let opposite_line = pair.1
    if opposite_line is Some(opposite_line) {
      while i < novel_opposite_lines.length() {
        let novel_opposite_line = novel_opposite_lines[i]
        if novel_opposite_line < opposite_line {
          merged.push((None, Some(novel_opposite_line)))
          i += 1
          continue
        }
        if novel_opposite_line == opposite_line {
          i += 1
          continue
        }
        break
      }
    }
    merged.push(pair)
  }
  while i < novel_opposite_lines.length() {
    merged.push((None, Some(novel_opposite_lines[i])))
    i += 1
  }
  merged
}

///|UUID(b31ba099-d334-47c6-b6a0-b0702b960446)
fn all_matched_lines(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> Array[(Int?, Int?)] {
  let lhs_matched_lines = matched_lines_from_unchanged(lhs_mps)
  let rhs_lines = all_lines(rhs_mps)
  let lines = merge_in_opposite_lines(lhs_matched_lines, rhs_lines)
  let lhs_lines = all_lines(lhs_mps)
  flip_line_pairs(merge_in_opposite_lines(flip_line_pairs(lines), lhs_lines))
}

///|UUID(ba69d93b-6545-4bd6-b603-6011b5577992)
// Extend matched lines to include leading and trailing file lines. Blank lines
// at file edges often have no syntax positions but still need stable alignment.
fn add_ends(
  matched_lines : ArrayView[(Int?, Int?)],
  lhs_line_count : Int,
  rhs_line_count : Int,
) -> Array[(Int?, Int?)] {
  let lhs_min = Ref(None)
  let rhs_min = Ref(None)
  for pair in matched_lines {
    let (lhs_line, rhs_line) = pair
    if lhs_min.val is None && lhs_line is Some(line) {
      lhs_min.val = Some(line)
    }
    if rhs_min.val is None && rhs_line is Some(line) {
      rhs_min.val = Some(line)
    }
    if lhs_min.val is Some(_) && rhs_min.val is Some(_) {
      break
    }
  }

  let lhs_max = Ref(None)
  let rhs_max = Ref(None)
  let reversed = reversed_pairs(matched_lines)
  for pair in reversed {
    let (lhs_line, rhs_line) = pair
    if lhs_max.val is None && lhs_line is Some(line) {
      lhs_max.val = Some(line)
    }
    if rhs_max.val is None && rhs_line is Some(line) {
      rhs_max.val = Some(line)
    }
    if lhs_max.val is Some(_) && rhs_max.val is Some(_) {
      break
    }
  }

  let res = Array::new()
  match (lhs_min.val, rhs_min.val) {
    (Some(lhs_min), Some(rhs_min)) => {
      let mut lhs_line = 0
      let mut rhs_line = 0
      while lhs_line < lhs_min && rhs_line < rhs_min {
        res.push((Some(lhs_line), Some(rhs_line)))
        lhs_line += 1
        rhs_line += 1
      }
      while lhs_line < lhs_min {
        res.push((Some(lhs_line), None))
        lhs_line += 1
      }
      while rhs_line < rhs_min {
        res.push((None, Some(rhs_line)))
        rhs_line += 1
      }
    }
    _ => ()
  }

  res.push_iter(matched_lines.iter())

  match (lhs_max.val, rhs_max.val) {
    (Some(lhs_max), Some(rhs_max)) => {
      let mut lhs_line = lhs_max + 1
      let mut rhs_line = rhs_max + 1
      while lhs_line < lhs_line_count && rhs_line < rhs_line_count {
        res.push((Some(lhs_line), Some(rhs_line)))
        lhs_line += 1
        rhs_line += 1
      }
      while lhs_line < lhs_line_count {
        res.push((Some(lhs_line), None))
        lhs_line += 1
      }
      while rhs_line < rhs_line_count {
        res.push((None, Some(rhs_line)))
        rhs_line += 1
      }
    }
    _ => ()
  }
  res
}

///|UUID(c20590f8-530c-4f8b-9ad9-5e99894e8876)
// If blank lines immediately precede the current matched pair on both sides,
// pair those blanks too. This improves visual alignment around sparse syntax.
fn match_blanks_between(
  current : (Int, Int),
  prev : (Int, Int),
  lhs_lines : ArrayView[String],
  rhs_lines : ArrayView[String],
) -> Array[(Int?, Int?)] {
  let mut current_lhs = current.0
  let mut current_rhs = current.1
  if current_lhs == 0 || current_rhs == 0 {
    return []
  }

  current_lhs -= 1
  current_rhs -= 1

  let matched = Array::new()
  while current_lhs > prev.0 && current_rhs > prev.1 {
    if lhs_lines[current_lhs] == "" && rhs_lines[current_rhs] == "" {
      matched.push((Some(current_lhs), Some(current_rhs)))
      current_lhs -= 1
      current_rhs -= 1
    } else {
      break
    }
  }
  reversed_pairs(matched)
}

///|UUID(1ca7d2c0-48c9-4aeb-8a7d-fe55ebbd2e63)
fn match_blanks_before(
  current : (Int, Int),
  lhs_lines : ArrayView[String],
  rhs_lines : ArrayView[String],
) -> Array[(Int?, Int?)] {
  let mut current_lhs = current.0
  let mut current_rhs = current.1
  if current_lhs == 0 || current_rhs == 0 {
    return []
  }

  current_lhs -= 1
  current_rhs -= 1

  let matched = Array::new()
  while true {
    if lhs_lines[current_lhs] == "" && rhs_lines[current_rhs] == "" {
      matched.push((Some(current_lhs), Some(current_rhs)))
      if current_lhs == 0 || current_rhs == 0 {
        break
      }
      current_lhs -= 1
      current_rhs -= 1
    } else {
      break
    }
  }
  reversed_pairs(matched)
}

///|UUID(267ec904-c05a-4bba-8acf-9488c7d3b8ce)
// Add preceding blank-line matches for every anchored pair. Following blank
// lines are handled by filling contiguous gaps after all anchors are known.
fn match_preceding_blanks(
  line_nums : ArrayView[(Int?, Int?)],
  lhs_lines : ArrayView[String],
  rhs_lines : ArrayView[String],
) -> Array[(Int?, Int?)] {
  let prev_lhs = Ref(None)
  let prev_rhs = Ref(None)
  let matched = Array::new()
  for pair in line_nums {
    match (pair.0, pair.1, prev_lhs.val, prev_rhs.val) {
      (Some(lhs_line), Some(rhs_line), None, None) =>
        matched.push_iter(
          match_blanks_before((lhs_line, rhs_line), lhs_lines, rhs_lines).iter(),
        )
      (Some(lhs_line), Some(rhs_line), Some(prev_lhs), Some(prev_rhs)) =>
        matched.push_iter(
          match_blanks_between(
            (lhs_line, rhs_line),
            (prev_lhs, prev_rhs),
            lhs_lines,
            rhs_lines,
          ).iter(),
        )
      _ => ()
    }
    matched.push(pair)
    if pair.0 is Some(line) {
      prev_lhs.val = Some(line)
    }
    if pair.1 is Some(line) {
      prev_rhs.val = Some(line)
    }
  }
  matched
}

///|UUID(a25a4c74-48e8-4578-9c20-d1a02ce224b3)
// Ensure intermediate source lines are not skipped. Missing LHS/RHS lines are
// inserted as one-sided pairs so renderers can preserve outer gaps.
fn ensure_contiguous(lines : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let contiguous = Array::new()
  let lhs_prev = Ref(None)
  let rhs_prev = Ref(None)
  for pair in lines {
    let (lhs_line, rhs_line) = pair
    if lhs_line is Some(line) {
      if lhs_prev.val is Some(prev) && prev + 1 != line {
        for gap_line in (prev + 1)..<line {
          contiguous.push((Some(gap_line), None))
        }
      }
      lhs_prev.val = Some(line)
    }
    if rhs_line is Some(line) {
      if rhs_prev.val is Some(prev) && prev + 1 != line {
        for gap_line in (prev + 1)..<line {
          contiguous.push((None, Some(gap_line)))
        }
      }
      rhs_prev.val = Some(line)
    }
    contiguous.push(pair)
  }
  contiguous
}

///|UUID(8cbf444a-380a-4ce0-b6eb-fd231b6517fd)
fn flush_gap_run(
  compacted : Array[(Int?, Int?)],
  lhs_unpaired : ArrayView[Int],
  rhs_unpaired : ArrayView[Int],
) -> Unit {
  if lhs_unpaired.length() == 1 && rhs_unpaired.length() == 1 {
    compacted.push((Some(lhs_unpaired[0]), Some(rhs_unpaired[0])))
  } else {
    for lhs_line in lhs_unpaired {
      compacted.push((Some(lhs_line), None))
    }
    for rhs_line in rhs_unpaired {
      compacted.push((None, Some(rhs_line)))
    }
  }
}

///|UUID(d1c26121-dd90-4c2e-8bf0-f532bbe21e25)
// Compact a single one-line gap from both sides into a paired row. Larger gaps
// stay separate to avoid implying unrelated lines are equal.
fn compact_gaps(items : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let compacted = Array::new()
  let lhs_unpaired = Array::new()
  let rhs_unpaired = Array::new()
  for pair in items {
    match pair {
      (Some(lhs_line), None) => lhs_unpaired.push(lhs_line)
      (None, Some(rhs_line)) => rhs_unpaired.push(rhs_line)
      _ => {
        flush_gap_run(compacted, lhs_unpaired, rhs_unpaired)
        lhs_unpaired.clear()
        rhs_unpaired.clear()
        compacted.push(pair)
      }
    }
  }
  flush_gap_run(compacted, lhs_unpaired, rhs_unpaired)
  compacted
}

///|UUID(64e67fe4-b776-4693-ad5e-2cda081ef617)
// Return all line pairs needed for rendering: unchanged anchors, novel lines,
// file edges, blank-line anchors, and contiguous gap fillers.
pub fn all_matched_lines_filled(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
  lhs_lines : ArrayView[String],
  rhs_lines : ArrayView[String],
) -> Array[(Int?, Int?)] {
  let matched_lines = add_ends(
    all_matched_lines(lhs_mps, rhs_mps),
    lhs_lines.length(),
    rhs_lines.length(),
  )
  compact_gaps(
    ensure_contiguous(
      match_preceding_blanks(matched_lines, lhs_lines, rhs_lines),
    ),
  )
}
