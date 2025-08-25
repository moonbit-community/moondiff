///|
pub fn align_edit_boundaries(
  input : ArrayView[Edit[Array[Char]]],
) -> Array[Edit[Array[Char]]] {
  let result = []
  loop input {
    [] => return result
    [
      Delete(old=current)
      | Insert(new=current) as middle,
      Equal(new=next, ..),
      .. rest,
    ] => {
      let last_element = result.pop()
      if last_element is Some(Equal(new=prev, ..)) {
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
          result.push(Equal(new=new_prev, old=[]))
          if middle is Delete(..) {
            result.push(Delete(old=new_current))
          } else {
            result.push(Insert(new=new_current))
          }
          result.push(Equal(new=new_next, old=[]))
        } else {
          let new_current = current[index_for_max_score_next + 1:].to_array() +
            next[:index_for_max_score_next + 1].to_array()
          let new_prev = prev +
            current[:index_for_max_score_next + 1].to_array()
          let new_next = next[index_for_max_score_next + 1:].to_array()
          result.push(Equal(new=new_prev, old=[]))
          if middle is Delete(..) {
            result.push(Delete(old=new_current))
          } else {
            result.push(Insert(new=new_current))
          }
          result.push(Equal(new=new_next, old=[]))
        }
      } else {
        if last_element is Some(edit) {
          result.push(edit)
        }
        result.push(middle)
        result.push(Equal(new=next, old=[]))
      }
      continue rest
    }
    [edit, .. rest] => {
      result.push(edit)
      continue rest
    }
  }
}

///|
fn fullfill_next_scoreboard(
  next_scoreboard : Array[Int],
  next_prefix_length : Int,
  next : Array[Char],
) -> Unit {
  if next_prefix_length == next.length() {
    next_scoreboard[next_prefix_length - 1] = 4 // max score
  }
  for i in 0..<next_prefix_length {
    match next[i + 1:] {
      [] => ()
      ['\n', ..] => next_scoreboard[i] = 3
      [' ', ..] | ['\t', ..] => next_scoreboard[i] = 2
      [ch, ..] => if ch is ('0'..='9') { next_scoreboard[i] = 1 }
    }
  }
}

///|
fn fullfill_prev_scoreboard(
  prev_scoreboard : Array[Int],
  prev_suffix_length : Int,
  prev : Array[Char],
) -> Unit {
  if prev_suffix_length == prev.length() {
    prev_scoreboard[prev_suffix_length - 1] = 4 // max score
  }
  for i in 0..<prev_suffix_length {
    match prev[:prev.length() - i] {
      [] => ()
      [.., '\n'] => prev_scoreboard[i] = 3
      [.., ' '] | [.., '\t'] => prev_scoreboard[i] = 2
      [.., ch] => if ch is ('0'..='9') { prev_scoreboard[i] = 1 }
    }
  }
}

///|
fn compute_common_prefix_length(
  x : ArrayView[Char],
  y : ArrayView[Char],
) -> Int {
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
test "compute_common_prefix_length" {
  inspect(
    compute_common_prefix_length(['a', 'b', 'c'], ['a', 'b', 'd']),
    content="2",
  )
  inspect(
    compute_common_prefix_length(['a', 'b', 'c'], ['a', 'b', 'c']),
    content="3",
  )
  inspect(
    compute_common_prefix_length(['a', 'b', 'c'], ['x', 'y', 'z']),
    content="0",
  )
  inspect(compute_common_prefix_length([], ['a', 'b', 'c']), content="0")
  inspect(compute_common_prefix_length(['a', 'b', 'c'], []), content="0")
  inspect(compute_common_prefix_length([], []), content="0")
}

///|
fn compute_common_suffix_length(
  x : ArrayView[Char],
  y : ArrayView[Char],
) -> Int {
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
