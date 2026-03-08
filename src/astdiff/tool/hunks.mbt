///|UUID(43ea7bcf-0a8b-449e-aac4-dc8c0b633959)
type LineSet = @hashmap.HashMap[Int, Bool]

///|UUID(9675cda4-4b44-406d-9128-9d311f3dd4e7)
type OppositeMap = @hashmap.HashMap[Int, Array[Int]]

///|UUID(25fa302a-c9b4-48a4-ba05-4ea0b5d672bd)
priv enum DisplaySide {
  Left
  Right
}

///|UUID(041c85e4-e4b3-4134-8363-2fcaa3baee16)
priv struct AstHunk {
  novel_lhs : LineSet
  novel_rhs : LineSet
  lines : Array[(Int?, Int?)]
}

///|UUID(2e358b6e-82df-4236-8652-859c7030f9c3)
fn copy_line_set(lines : LineSet) -> LineSet {
  let copied = @hashmap.HashMap::new()
  for line, _ in lines {
    copied.set(line, true)
  }
  copied
}

///|UUID(9379de66-12f9-41b8-bbd1-fe07dc747699)
fn AstHunk::merge(self : Self, other : Self) -> Self {
  let lines = self.lines.copy()
  lines.push_iter(other.lines.iter())

  let lhs_seen = @hashmap.HashMap::new()
  let rhs_seen = @hashmap.HashMap::new()
  let deduped = Array::new()
  for pair in lines {
    let (lhs_line, rhs_line) = pair
    let lhs_is_dupe = if lhs_line is Some(line) {
      let seen = lhs_seen.contains(line)
      lhs_seen.set(line, true)
      seen
    } else {
      false
    }
    let rhs_is_dupe = if rhs_line is Some(line) {
      let seen = rhs_seen.contains(line)
      rhs_seen.set(line, true)
      seen
    } else {
      false
    }
    if lhs_is_dupe && rhs_is_dupe {
      continue
    }
    deduped.push(
      (
        if lhs_is_dupe {
          None
        } else {
          lhs_line
        },
        if rhs_is_dupe {
          None
        } else {
          rhs_line
        },
      ),
    )
  }

  let novel_lhs = copy_line_set(self.novel_lhs)
  let novel_rhs = copy_line_set(self.novel_rhs)
  for line, _ in other.novel_lhs {
    novel_lhs.set(line, true)
  }
  for line, _ in other.novel_rhs {
    novel_rhs.set(line, true)
  }
  AstHunk::{ novel_lhs, novel_rhs, lines: deduped }
}

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
fn opposite_positions(mps : ArrayView[MatchedPos]) -> OppositeMap {
  let opposites = @hashmap.HashMap::new()
  for mp in mps {
    match mp.kind {
      Unchanged(opposite_pos~) => {
        let self_line = line_index(mp.pos)
        for opposite in opposite_pos {
          add_opposite_line(opposites, self_line, line_index(opposite))
        }
      }
      Novel => ()
    }
  } nobreak {
    opposites
  }
}

///|UUID(1be4c24f-d501-4268-a7fc-4cc39f737bcf)
fn lines_with_novel(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> (LineSet, LineSet) {
  let lhs_lines = @hashmap.HashMap::new()
  let rhs_lines = @hashmap.HashMap::new()
  for mp in lhs_mps {
    if mp.kind.is_novel() {
      push_line(lhs_lines, line_index(mp.pos))
    }
  }
  for mp in rhs_mps {
    if mp.kind.is_novel() {
      push_line(rhs_lines, line_index(mp.pos))
    }
  }
  (lhs_lines, rhs_lines)
}

///|UUID(67f1ba22-01fd-49b9-884e-b047dd93fe23)
fn all_lines(mps : ArrayView[MatchedPos]) -> Array[Int] {
  let seen = @hashmap.HashMap::new()
  for mp in mps {
    let line = line_index(mp.pos)
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

///|UUID(67a63f65-6783-4f4d-a6cf-fc5ef332643a)
fn next_opposite_line(
  opposite_pos : ArrayView[@span.SingleLineSpan],
  prev_opposite : Int?,
) -> Int? {
  let lines = Array::new()
  for opposite in opposite_pos {
    let line = line_index(opposite)
    if line >= 0 && !lines.contains(line) {
      lines.push(line)
    }
  }
  lines.sort()
  for line in lines {
    if prev_opposite is Some(prev) {
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
fn matched_lines_from_unchanged(
  mps : ArrayView[MatchedPos],
) -> Array[(Int?, Int?)] {
  let highest_line = Ref::new(None)
  let highest_opposite_line = Ref::new(None)
  let matched = Array::new()
  for mp in mps {
    let self_line = line_index(mp.pos)
    if self_line < 0 {
      continue
    }
    let opposite_line = match mp.kind {
      Unchanged(opposite_pos~) =>
        next_opposite_line(opposite_pos, highest_opposite_line.val)
      Novel => None
    }
    guard opposite_line is Some(opposite_line) else { continue }

    let should_insert = match highest_line.val {
      Some(highest) => self_line > highest
      None => true
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
fn add_ends(
  matched_lines : ArrayView[(Int?, Int?)],
  lhs_line_count : Int,
  rhs_line_count : Int,
) -> Array[(Int?, Int?)] {
  let lhs_min = Ref::new(None)
  let rhs_min = Ref::new(None)
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

  let lhs_max = Ref::new(None)
  let rhs_max = Ref::new(None)
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
fn match_preceding_blanks(
  line_nums : ArrayView[(Int?, Int?)],
  lhs_lines : ArrayView[String],
  rhs_lines : ArrayView[String],
) -> Array[(Int?, Int?)] {
  let prev_lhs = Ref::new(None)
  let prev_rhs = Ref::new(None)
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
fn ensure_contiguous(lines : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let contiguous = Array::new()
  let lhs_prev = Ref::new(None)
  let rhs_prev = Ref::new(None)
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

///|UUID(d1c26121-dd90-4c2e-8bf0-f532bbe21e25)
fn compact_gaps(items : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let compacted = Array::new()
  let unpaired = Array::new()
  for pair in items {
    match pair {
      (Some(lhs_line), None) =>
        match unpaired.get(0) {
          Some((None, Some(rhs_line))) => {
            compacted.push((Some(lhs_line), Some(rhs_line)))
            ignore(unpaired.remove(0))
          }
          _ => unpaired.push(pair)
        }
      (None, Some(rhs_line)) =>
        match unpaired.get(0) {
          Some((Some(lhs_line), None)) => {
            compacted.push((Some(lhs_line), Some(rhs_line)))
            ignore(unpaired.remove(0))
          }
          _ => unpaired.push(pair)
        }
      _ => {
        compacted.push_iter(unpaired.iter())
        unpaired.clear()
        compacted.push(pair)
      }
    }
  }
  compacted.push_iter(unpaired.iter())
  compacted
}

///|UUID(64e67fe4-b776-4693-ad5e-2cda081ef617)
fn all_matched_lines_filled(
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

///|UUID(6e2c5291-f077-4d50-ac37-ca3578e859df)
fn novel_section_in_order(
  lhs_novel_mps : ArrayView[MatchedPos],
  rhs_novel_mps : ArrayView[MatchedPos],
  lhs_prev_matched_line : Int?,
  rhs_prev_matched_line : Int?,
  opposite_to_lhs : OppositeMap,
  opposite_to_rhs : OppositeMap,
) -> Array[(DisplaySide, MatchedPos)] {
  let ordered = Array::new()
  let mut lhs_i = 0
  let mut rhs_i = 0

  while lhs_i < lhs_novel_mps.length() {
    let lhs_mp = lhs_novel_mps[lhs_i]
    if lhs_prev_matched_line is Some(prev) && line_index(lhs_mp.pos) == prev {
      ordered.push((Left, lhs_mp))
      lhs_i += 1
    } else {
      break
    }
  }
  while rhs_i < rhs_novel_mps.length() {
    let rhs_mp = rhs_novel_mps[rhs_i]
    if rhs_prev_matched_line is Some(prev) && line_index(rhs_mp.pos) == prev {
      ordered.push((Right, rhs_mp))
      rhs_i += 1
    } else {
      break
    }
  }

  while lhs_i < lhs_novel_mps.length() {
    let lhs_mp = lhs_novel_mps[lhs_i]
    if opposite_to_lhs.contains(line_index(lhs_mp.pos)) {
      break
    }
    ordered.push((Left, lhs_mp))
    lhs_i += 1
  }
  while rhs_i < rhs_novel_mps.length() {
    let rhs_mp = rhs_novel_mps[rhs_i]
    if opposite_to_rhs.contains(line_index(rhs_mp.pos)) {
      break
    }
    ordered.push((Right, rhs_mp))
    rhs_i += 1
  }

  for i in lhs_i..<lhs_novel_mps.length() {
    ordered.push((Left, lhs_novel_mps[i]))
  }
  for i in rhs_i..<rhs_novel_mps.length() {
    ordered.push((Right, rhs_novel_mps[i]))
  }
  ordered
}

///|UUID(f521588c-0a9f-4cc0-92a9-b5195a681588)
fn sorted_novel_positions(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
  opposite_to_lhs : OppositeMap,
  opposite_to_rhs : OppositeMap,
) -> Array[(DisplaySide, MatchedPos)] {
  let ordered = Array::new()
  let lhs_novel_section = Array::new()
  let rhs_novel_section = Array::new()
  let mut lhs_prev_matched_line = None
  let mut rhs_prev_matched_line = None
  let mut lhs_i = 0
  let mut rhs_i = 0

  while lhs_i < lhs_mps.length() || rhs_i < rhs_mps.length() {
    match (lhs_mps.get(lhs_i), rhs_mps.get(rhs_i)) {
      (Some(lhs_mp), Some(rhs_mp)) if !lhs_mp.kind.is_novel() &&
        !rhs_mp.kind.is_novel() => {
        ordered.push_iter(
          novel_section_in_order(
            lhs_novel_section, rhs_novel_section, lhs_prev_matched_line, rhs_prev_matched_line,
            opposite_to_lhs, opposite_to_rhs,
          ).iter(),
        )
        lhs_novel_section.clear()
        rhs_novel_section.clear()
        lhs_prev_matched_line = Some(line_index(lhs_mp.pos))
        rhs_prev_matched_line = Some(line_index(rhs_mp.pos))
        lhs_i += 1
        rhs_i += 1
      }
      (Some(lhs_mp), _) if lhs_mp.kind.is_novel() => {
        lhs_novel_section.push(lhs_mp)
        lhs_i += 1
      }
      (_, Some(rhs_mp)) if rhs_mp.kind.is_novel() => {
        rhs_novel_section.push(rhs_mp)
        rhs_i += 1
      }
      (None, None) => ()
      _ => panic()
    }
  }

  ordered.push_iter(
    novel_section_in_order(
      lhs_novel_section, rhs_novel_section, lhs_prev_matched_line, rhs_prev_matched_line,
      opposite_to_lhs, opposite_to_rhs,
    ).iter(),
  )
  ordered
}

///|UUID(edb01f4c-b0af-4901-bc1e-f46dc7378ac0)
fn next_opposite(
  line : Int,
  opposites : OppositeMap,
  prev_opposite : Int?,
) -> Int? {
  match opposites.get(line) {
    Some(lines) => {
      for opposite in lines {
        if prev_opposite is Some(prev) {
          if opposite > prev {
            return Some(opposite)
          }
        } else {
          return Some(opposite)
        }
      }
      None
    }
    None => None
  }
}

///|UUID(4582d1f3-9b37-48ec-a0ec-accb93251406)
fn matched_novel_lines(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> Array[(Int?, Int?)] {
  let highest_lhs = Ref::new(None)
  let highest_rhs = Ref::new(None)
  let opposite_to_lhs = opposite_positions(lhs_mps)
  let opposite_to_rhs = opposite_positions(rhs_mps)
  let lines = Array::new()

  for
    entry in sorted_novel_positions(
      lhs_mps, rhs_mps, opposite_to_lhs, opposite_to_rhs,
    ) {
    let (side, mp) = entry
    let self_line = line_index(mp.pos)
    match side {
      Left =>
        if highest_lhs.val is Some(highest) {
          if self_line > highest {
            lines.push(
              (
                Some(self_line),
                next_opposite(self_line, opposite_to_lhs, highest_rhs.val),
              ),
            )
            highest_lhs.val = Some(self_line)
          }
        } else {
          lines.push(
            (
              Some(self_line),
              next_opposite(self_line, opposite_to_lhs, highest_rhs.val),
            ),
          )
          highest_lhs.val = Some(self_line)
        }
      Right =>
        if highest_rhs.val is Some(highest) {
          if self_line > highest {
            lines.push(
              (
                next_opposite(self_line, opposite_to_rhs, highest_lhs.val),
                Some(self_line),
              ),
            )
            highest_rhs.val = Some(self_line)
          }
        } else {
          lines.push(
            (
              next_opposite(self_line, opposite_to_rhs, highest_lhs.val),
              Some(self_line),
            ),
          )
          highest_rhs.val = Some(self_line)
        }
    }
  }
  lines
}

///|UUID(1ff98ba2-048e-4df1-9bd1-87b329990fc1)
fn lines_are_close(max_lhs : Int?, max_rhs : Int?, line : (Int?, Int?)) -> Bool {
  let (lhs, rhs) = line
  match (max_lhs, lhs) {
    (Some(max_lhs), Some(lhs)) => if lhs <= max_lhs + 4 { return true }
    _ => ()
  }
  match (max_rhs, rhs) {
    (Some(max_rhs), Some(rhs)) => if rhs <= max_rhs + 4 { return true }
    _ => ()
  }
  false
}

///|UUID(54ad6d0d-c800-4b85-b893-7f72f303b7d4)
fn next_increasing(max_seen : Int?, line : Int?) -> Int? {
  match (max_seen, line) {
    (Some(max_seen), Some(line)) =>
      if line > max_seen {
        Some(line)
      } else {
        None
      }
    (None, Some(line)) => Some(line)
    _ => None
  }
}

///|UUID(fa17a4ac-2948-4c91-a892-3a8f4e9d2fe6)
fn update_max(max_seen : Ref[Int?], line : Int?) -> Unit {
  if line is Some(line) {
    max_seen.val = Some(line)
  }
}

///|UUID(d7298dd9-6fd5-484c-93f4-f14151798ee5)
fn fill_increasing_line(max_seen : Ref[Int?], line : Int?) -> Int? {
  let next_line = next_increasing(max_seen.val, line)
  update_max(max_seen, next_line)
  next_line
}

///|UUID(f583e103-7bd9-4e38-ae85-51cb86af6dee)
fn enforce_increasing(lines : ArrayView[(Int?, Int?)]) -> Array[(Int?, Int?)] {
  let ordered = Array::new()
  let max_lhs = Ref::new(None)
  let max_rhs = Ref::new(None)
  for pair in lines {
    let lhs_line = fill_increasing_line(max_lhs, pair.0)
    let rhs_line = fill_increasing_line(max_rhs, pair.1)
    if lhs_line is Some(_) || rhs_line is Some(_) {
      ordered.push((lhs_line, rhs_line))
    }
  }
  ordered
}

///|UUID(fc86b81e-d7a2-4fa6-9289-e50794a18993)
fn find_novel_lines(
  lines : ArrayView[(Int?, Int?)],
  all_lhs_novel : LineSet,
  all_rhs_novel : LineSet,
) -> (LineSet, LineSet) {
  let lhs_novel = @hashmap.HashMap::new()
  let rhs_novel = @hashmap.HashMap::new()
  for pair in lines {
    let (lhs_line, rhs_line) = pair
    if lhs_line is Some(line) && all_lhs_novel.contains(line) {
      push_line(lhs_novel, line)
    }
    if rhs_line is Some(line) && all_rhs_novel.contains(line) {
      push_line(rhs_novel, line)
    }
  }
  (lhs_novel, rhs_novel)
}

///|UUID(ed4c5395-1afb-48dc-8af0-cde52c38e55e)
fn lines_to_hunks(
  lines : ArrayView[(Int?, Int?)],
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> Array[AstHunk] {
  let (all_lhs_novel, all_rhs_novel) = lines_with_novel(lhs_mps, rhs_mps)
  let hunks = Array::new()
  let current_hunk_lines = Array::new()
  let max_lhs = Ref::new(None)
  let max_rhs = Ref::new(None)

  for line in enforce_increasing(lines) {
    let (lhs_line, rhs_line) = line
    if current_hunk_lines.is_empty() ||
      lines_are_close(max_lhs.val, max_rhs.val, line) {
      current_hunk_lines.push(line)
    } else {
      let (novel_lhs, novel_rhs) = find_novel_lines(
        current_hunk_lines, all_lhs_novel, all_rhs_novel,
      )
      hunks.push(AstHunk::{
        novel_lhs,
        novel_rhs,
        lines: current_hunk_lines.copy(),
      })
      current_hunk_lines.clear()
      current_hunk_lines.push(line)
    }
    if lhs_line is Some(line) {
      max_lhs.val = Some(line)
    }
    if rhs_line is Some(line) {
      max_rhs.val = Some(line)
    }
  }

  if !current_hunk_lines.is_empty() {
    let (novel_lhs, novel_rhs) = find_novel_lines(
      current_hunk_lines, all_lhs_novel, all_rhs_novel,
    )
    hunks.push(AstHunk::{ novel_lhs, novel_rhs, lines: current_hunk_lines })
  }
  hunks
}

///|UUID(160566ec-5965-45cc-bc44-0e630b4bd1fb)
fn matched_pos_to_hunks(
  lhs_mps : ArrayView[MatchedPos],
  rhs_mps : ArrayView[MatchedPos],
) -> Array[AstHunk] {
  lines_to_hunks(matched_novel_lines(lhs_mps, rhs_mps), lhs_mps, rhs_mps)
}

///|UUID(e8149d12-9789-4f7a-b999-e5855bda3518)
fn fill_between(
  prev_lhs : Int?,
  next_lhs : Int?,
  prev_rhs : Int?,
  next_rhs : Int?,
) -> Array[(Int?, Int?)] {
  let lhs_lines = Array::new()
  let rhs_lines = Array::new()
  match (prev_lhs, next_lhs) {
    (Some(prev_lhs), Some(next_lhs)) =>
      if prev_lhs + 1 < next_lhs {
        for line in (prev_lhs + 1)..<next_lhs {
          lhs_lines.push(line)
        }
      }
    _ => ()
  }
  match (prev_rhs, next_rhs) {
    (Some(prev_rhs), Some(next_rhs)) =>
      if prev_rhs + 1 < next_rhs {
        for line in (prev_rhs + 1)..<next_rhs {
          rhs_lines.push(line)
        }
      }
    _ => ()
  }
  let filled = Array::new()
  let limit = if lhs_lines.length() > rhs_lines.length() {
    lhs_lines.length()
  } else {
    rhs_lines.length()
  }
  for i in 0..<limit {
    let lhs_line : Int? = lhs_lines.get(i)
    let rhs_line : Int? = rhs_lines.get(i)
    filled.push((lhs_line, rhs_line))
  }
  filled
}

///|UUID(97feb0f2-c6cc-4093-9c13-6870ac972bb3)
fn extract_hunk_lines(hunk : AstHunk) -> Array[(Int?, Int?)] {
  let relevant = Array::new()
  let max_lhs = Ref::new(None)
  let max_rhs = Ref::new(None)
  for pair in hunk.lines {
    let (lhs_line, rhs_line) = pair
    relevant.push_iter(
      fill_between(max_lhs.val, lhs_line, max_rhs.val, rhs_line).iter(),
    )
    relevant.push(pair)
    if lhs_line is Some(line) {
      max_lhs.val = Some(line)
    }
    if rhs_line is Some(line) {
      max_rhs.val = Some(line)
    }
  }
  relevant
}

///|UUID(e2071738-353c-470e-9815-760d318ccd39)
fn hunk_line_sets(hunk : AstHunk) -> (LineSet, LineSet) {
  let lhs_lines = @hashmap.HashMap::new()
  let rhs_lines = @hashmap.HashMap::new()
  for pair in extract_hunk_lines(hunk) {
    if pair.0 is Some(line) {
      lhs_lines.set(line, true)
    }
    if pair.1 is Some(line) {
      rhs_lines.set(line, true)
    }
  }
  (lhs_lines, rhs_lines)
}

///|UUID(37df1400-5ca1-41eb-b615-f333eaba87b5)
fn matched_lines_indexes_for_hunk(
  hunk : AstHunk,
  matched_lines : ArrayView[(Int?, Int?)],
) -> (Int, Int) {
  let (lhs_lines, rhs_lines) = hunk_line_sets(hunk)
  let start = Ref::new(None)
  let end_ = Ref::new(None)
  for i in 0..<matched_lines.length() {
    let pair = matched_lines[i]
    let contains_line = (pair.0 is Some(line) && lhs_lines.contains(line)) ||
      (pair.1 is Some(line) && rhs_lines.contains(line))
    if contains_line {
      if start.val is None {
        start.val = Some(i)
      }
      end_.val = Some(i + 1)
    }
  }
  match (start.val, end_.val) {
    (Some(start), Some(end_)) => (start, end_)
    _ => (0, matched_lines.length())
  }
}

///|UUID(ccd8a955-311f-4247-ad00-a5f62b63de43)
fn contextual_index_range_for_hunk(
  hunk : AstHunk,
  matched_lines : ArrayView[(Int?, Int?)],
  radius : Int,
) -> (Int, Int) {
  let (start, end_) = matched_lines_indexes_for_hunk(hunk, matched_lines)
  (
    @cmp.maximum(start - radius, 0),
    @cmp.minimum(end_ + radius, matched_lines.length()),
  )
}

///|UUID(6249eec7-8cf2-468c-b6fa-01f689dd04c8)
fn merge_adjacent_hunks(
  hunks : ArrayView[AstHunk],
  matched_lines : ArrayView[(Int?, Int?)],
  context_lines : Int,
) -> Array[AstHunk] {
  let merged = Array::new()
  let prev_hunk = Ref::new(None)
  let prev_start = Ref::new(0)
  let prev_end = Ref::new(0)

  let merge_radius = context_lines + 1
  for hunk in hunks {
    let (start, end_) = contextual_index_range_for_hunk(
      hunk, matched_lines, merge_radius,
    )
    match prev_hunk.val {
      Some(prev) =>
        if start > prev_end.val {
          merged.push(prev)
          prev_hunk.val = Some(hunk)
          prev_start.val = start
          prev_end.val = end_
        } else {
          prev_hunk.val = Some(prev.merge(hunk))
          prev_start.val = @cmp.minimum(prev_start.val, start)
          prev_end.val = @cmp.maximum(prev_end.val, end_)
        }
      None => {
        prev_hunk.val = Some(hunk)
        prev_start.val = start
        prev_end.val = end_
      }
    }
  }

  if prev_hunk.val is Some(hunk) {
    merged.push(hunk)
  }
  merged
}
