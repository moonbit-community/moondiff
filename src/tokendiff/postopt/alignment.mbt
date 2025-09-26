///|
pub fn align_edit_boundaries(
  input : ArrayView[Edit[Array[MbtToken]]],
) -> Array[Edit[Array[MbtToken]]] {
  let result = []
  for edit in input {
    result.push_edit(edit)
    match result {
      [.., Delete(old=prev), Insert(new=current), Equal(new=next, ..)] => {
        let next_length = next.length()
        if next_length < current.length() / 3 || next_length < prev.length() / 3 {
          result.truncate(result.length() - 3)
          let prefix = Array::new(capacity=next_length)
          let mut rest = next[:]
          while rest != [] && not_trailing_endmark(rest) {
            prefix.push(rest[0])
            rest = rest[1:]
          }
          result.push_edit(Delete(old=prev + prefix))
          result.push_edit(Insert(new=current + prefix))
          if rest != [] {
            result.push_edit(Equal(new=rest.to_array(), old=[]))
          }
        }
      }
      [
        ..,
        Equal(new=prev, ..),
        Delete(old=current)
        | Insert(new=current) as middle,
        Equal(new=next, ..),
      ] => {
        result.truncate(result.length() - 3)
        let prev_suffix_length = compute_common_suffix_length(current, prev)
        let next_prefix_length = compute_common_prefix_length(current, next)
        let prev_scoreboard = Array::make(prev_suffix_length, 0)
        let next_scoreboard = Array::make(next_prefix_length, 0)
        // fullfill next_scoreboard
        fullfill_next_scoreboard(next_scoreboard, next_prefix_length, next)
        // fullfill prev_scoreboard
        fullfill_prev_scoreboard(prev_scoreboard, prev_suffix_length, prev)
        // try to find max score from next_scoreboard
        let mut max_score_for_next = 0
        let mut index_for_max_score_next = -1
        for i in 0..<next_scoreboard.length() {
          if next_scoreboard[i] > max_score_for_next {
            max_score_for_next = next_scoreboard[i]
            index_for_max_score_next = i
          }
        }
        // try to find max score from prev_scoreboard
        let mut max_score_for_prev = 0
        let mut index_for_max_score_prev = -1
        for i in 0..<prev_scoreboard.length() {
          if prev_scoreboard[i] > max_score_for_prev {
            max_score_for_prev = prev_scoreboard[i]
            index_for_max_score_prev = i
          }
        }
        if max_score_for_prev > max_score_for_next {
          let new_current = prev[prev.length() - index_for_max_score_prev - 1:].to_array() +
            current[:current.length() - index_for_max_score_prev - 1].to_array()
          let new_next = current[current.length() - index_for_max_score_prev - 1:].to_array() +
            next
          let new_prev = prev[:prev.length() - index_for_max_score_prev - 1].to_array()
          result.push_edit(Equal(new=new_prev, old=[]))
          if middle is Delete(..) {
            result.push_edit(Delete(old=new_current))
          } else {
            result.push_edit(Insert(new=new_current))
          }
          result.push_edit(Equal(new=new_next, old=[]))
        } else {
          let new_current = current[index_for_max_score_next + 1:].to_array() +
            next[:index_for_max_score_next + 1].to_array()
          let new_prev = prev +
            current[:index_for_max_score_next + 1].to_array()
          let new_next = next[index_for_max_score_next + 1:].to_array()
          result.push_edit(Equal(new=new_prev, old=[]))
          if middle is Delete(..) {
            result.push_edit(Delete(old=new_current))
          } else {
            result.push_edit(Insert(new=new_current))
          }
          result.push_edit(Equal(new=new_next, old=[]))
        }
      }
      _ => continue
    }
  } else {
    return result
  }
}

///|
fn not_trailing_endmark(input : ArrayView[MbtToken]) -> Bool {
  not(
    input is [Invisible(repr~, ..), ..] &&
    repr.contains('\n') &&
    input is [.., Visible(kind=TK_RBRACKET, ..)],
  )
}

///|
fn fullfill_next_scoreboard(
  next_scoreboard : Array[Int],
  next_prefix_length : Int,
  next : Array[MbtToken],
) -> Unit {
  if next_prefix_length == next.length() {
    next_scoreboard[next_prefix_length - 1] = 4 // max score
  }
  for i in 0..<next_prefix_length {
    match next[i] {
      Invisible(repr~, ..) =>
        if repr.contains('\n') {
          next_scoreboard[i] = 3
        } else {
          next_scoreboard[i] = 2
        }
      Visible(kind~, ..) => if kind is TK_INT { next_scoreboard[i] = 1 }
      _ => ()
    }
  }
}

///|
fn fullfill_prev_scoreboard(
  prev_scoreboard : Array[Int],
  prev_suffix_length : Int,
  prev : Array[MbtToken],
) -> Unit {
  if prev_suffix_length == prev.length() {
    prev_scoreboard[prev_suffix_length - 1] = 4 // max score
  }
  for i in 0..<prev_suffix_length {
    match prev[prev.length() - i - 1] {
      Invisible(repr~, ..) =>
        if repr.contains('\n') {
          prev_scoreboard[i] = 3
        } else {
          prev_scoreboard[i] = 2
        }
      Visible(kind~, ..) => if kind is TK_INT { prev_scoreboard[i] = 1 }
      _ => ()
    }
  }
}

///|
fn compute_common_prefix_length(
  x : ArrayView[MbtToken],
  y : ArrayView[MbtToken],
) -> Int {
  // assume multiple invisible tokens are merged before call this function
  let mut prefix_length = 0
  loop (x, y) {
    ([], []) => return prefix_length
    ([], _) => return prefix_length
    (_, []) => return prefix_length
    ([x_hd, .. x_rest], [y_hd, .. y_rest]) =>
      if x_hd == y_hd {
        prefix_length += 1
        continue (x_rest, y_rest)
      } else {
        return prefix_length
      }
  }
}

///|
fn compute_common_suffix_length(
  x : ArrayView[MbtToken],
  y : ArrayView[MbtToken],
) -> Int {
  // assume multiple invisible tokens are merged before call this function
  let mut suffix_length = 0
  loop (x, y) {
    ([], []) => return suffix_length
    ([], _) => return suffix_length
    (_, []) => return suffix_length
    ([.. x_rest, x_last], [.. y_rest, y_last]) =>
      if x_last == y_last {
        suffix_length += 1
        continue (x_rest, y_rest)
      } else {
        return suffix_length
      }
  }
}

///|
fn Array::push_edit(
  self : Array[Edit[Array[MbtToken]]],
  edit : Edit[Array[MbtToken]],
) -> Unit {
  match self {
    [] => self.push(edit)
    [.., last] =>
      match (last, edit) {
        (Delete(old=hd), Delete(old=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Delete(old=hd + tl))
        }
        (Insert(new=hd), Insert(new=tl)) => {
          self.truncate(self.length() - 1)
          self.push(Insert(new=hd + tl))
        }
        (Equal(new=hd, ..), Equal(new=tl, ..)) => {
          self.truncate(self.length() - 1)
          self.push(Equal(new=hd + tl, old=[]))
        }
        _ => self.push(edit)
      }
  }
}
