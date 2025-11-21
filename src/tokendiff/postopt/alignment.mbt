///|UUID(039bd8a9-e2b3-4cda-a45b-3c4695e9d062)
pub fn align_edit_boundaries(
  input : ArrayView[Edit[Array[MbtToken]]],
) -> Array[Edit[Array[MbtToken]]] {
  let result = []
  for edit in input {
    result.push_edit(edit)
    match result {
      [
        ..,
        Delete(old=prev),
        Insert(new=current),
        Equal(new=next_new, old=next_old),
      ] => {
        /// +++ 
        let next_new_length = next_new.content_length()
        let next_old_length = next_old.content_length()
        if next_new_length < current.content_length() / 3 ||
          next_old_length < prev.content_length() / 3 {
          result.truncate(result.length() - 3)
          let new_prefix = Array::new(capacity=next_new_length)
          let old_prefix = Array::new(capacity=next_old_length)
          let mut new_rest = next_new[:]
          let mut old_rest = next_old[:]
          while new_rest != [] &&
                old_rest != [] &&
                not_a_trailing_endmark(new_rest) &&
                not_a_trailing_endmark(old_rest) {
            new_prefix.push(new_rest[0])
            old_prefix.push(old_rest[0])
            new_rest = new_rest[1:]
            old_rest = old_rest[1:]
          }
          result.push_edit(Delete(old=prev + old_prefix))
          result.push_edit(Insert(new=current + new_prefix))
          match (old_rest, new_rest) {
            ([], []) => ()
            (old_rest, new_rest) =>
              result.push_edit(
                Equal(new=new_rest.to_array(), old=old_rest.to_array()),
              )
          }
        }
      }
      [
        ..,
        Equal(new=prev, old=prev_old),
        Insert(new=current),
        Equal(new=next, old=next_old),
      ] => {
        result.truncate(result.length() - 3)
        let prev_suffix_length = compute_common_suffix_length(current, prev)
        let next_prefix_length = compute_common_prefix_length(current, next)
        let prev_scoreboard = Array::make(prev_suffix_length, 0)
        let next_scoreboard = Array::make(next_prefix_length, 0)
        // fullfill next_scoreboard
        fullfill_next_scoreboard(next_scoreboard, next)
        // fullfill prev_scoreboard
        fullfill_prev_scoreboard(prev_scoreboard, prev)
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
          let (prev, current, next) = slide_to_prev(
            prev~,
            current~,
            next~,
            index_for_max_score_prev~,
          )
          result.push_edit(Equal(new=prev, old=prev_old))
          result.push_edit(Insert(new=current))
          result.push_edit(Equal(new=next, old=next_old))
        } else {
          let (prev, current, next) = slide_to_next(
            prev~,
            current~,
            next~,
            index_for_max_score_next~,
          )
          result.push_edit(Equal(new=prev, old=prev_old))
          result.push_edit(Insert(new=current))
          result.push_edit(Equal(new=next, old=next_old))
        }
      }
      [
        ..,
        Equal(new=prev_new, old=prev),
        Delete(old=current),
        Equal(new=next_new, old=next),
      ] => {
        result.truncate(result.length() - 3)
        let prev_suffix_length = compute_common_suffix_length(current, prev)
        let next_prefix_length = compute_common_prefix_length(current, next)
        let prev_scoreboard = Array::make(prev_suffix_length, 0)
        let next_scoreboard = Array::make(next_prefix_length, 0)
        // fullfill next_scoreboard
        fullfill_next_scoreboard(next_scoreboard, next)
        // fullfill prev_scoreboard
        fullfill_prev_scoreboard(prev_scoreboard, prev)
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
          let (prev, current, next) = slide_to_prev(
            prev~,
            current~,
            next~,
            index_for_max_score_prev~,
          )
          result.push_edit(Equal(new=prev_new, old=prev))
          result.push_edit(Delete(old=current))
          result.push_edit(Equal(new=next_new, old=next))
        } else {
          let (prev, current, next) = slide_to_next(
            prev~,
            current~,
            next~,
            index_for_max_score_next~,
          )
          result.push_edit(Equal(new=prev_new, old=prev))
          result.push_edit(Delete(old=current))
          result.push_edit(Equal(new=next_new, old=next))
        }
      }
      _ => continue
    }
  } else {
    return result.remove_leading_trailing_blank()
  }
}

///|UUID(876a3bed-bf21-41bb-82b7-6407ba84dd24)
fn Array::content_length(self : Array[MbtToken]) -> Int {
  let mut length = 0
  for token in self {
    match token {
      Visible(repr~, ..) => length += repr.length()
      Invisible(repr) => {
        let mut width = 0
        for w in repr {
          if w == 0 {
            width += 1 // newline
          } else {
            width += w
          }
        }
        length += width
      }
      _ => ()
    }
  }
  return length
}

///|UUID(1e014ef8-949d-4260-83ab-5dfd70240f35)
/// avoid some anti pattern in Equal:
/// ```pesudo mbt
///    <newline>
/// <consecutive space> <tokens> <'}' or ']'> <consecutive space>
/// ```
fn not_a_trailing_endmark(input : ArrayView[MbtToken]) -> Bool {
  fn find_first_ocuurence(input : ArrayView[MbtToken]) -> ArrayView[MbtToken]? {
    match input {
      [] => None
      [Visible(kind=TK_RBRACE | TK_RBRACKET, ..), .. rest] => Some(rest)
      [_, .. rest] => find_first_ocuurence(rest)
    }
  }

  not(
    input is [Invisible(repr), .. rest] &&
    repr.contains(0) &&
    find_first_ocuurence(rest) is Some(maybe_invisible) &&
    (maybe_invisible is [] || maybe_invisible is [Invisible(_)]),
  )
}

///|UUID(c4c6b52c-9397-43d8-82b0-1c3c08193c10)
fn slide_to_prev(
  prev~ : Array[MbtToken],
  current~ : Array[MbtToken],
  next~ : Array[MbtToken],
  index_for_max_score_prev~ : Int,
) -> (Array[MbtToken], Array[MbtToken], Array[MbtToken]) {
  let new_current = prev[prev.length() - index_for_max_score_prev - 1:].to_array() +
    current[:current.length() - index_for_max_score_prev - 1].to_array()
  let new_next = current[current.length() - index_for_max_score_prev - 1:].to_array() +
    next
  let new_prev = prev[:prev.length() - index_for_max_score_prev - 1].to_array()
  (new_prev, new_current, new_next)
}

///|UUID(ccdd0800-803c-4285-8b26-d7360aafdb4d)
fn slide_to_next(
  prev~ : Array[MbtToken],
  current~ : Array[MbtToken],
  next~ : Array[MbtToken],
  index_for_max_score_next~ : Int,
) -> (Array[MbtToken], Array[MbtToken], Array[MbtToken]) {
  let new_current = current[index_for_max_score_next + 1:].to_array() +
    next[:index_for_max_score_next + 1].to_array()
  let new_prev = prev + current[:index_for_max_score_next + 1].to_array()
  let new_next = next[index_for_max_score_next + 1:].to_array()
  (new_prev, new_current, new_next)
}

///|UUID(583eb74c-6801-4447-9018-8db845a54a09)
fn fullfill_next_scoreboard(
  next_scoreboard : Array[Int],
  next : Array[MbtToken],
) -> Unit {
  let next_prefix_length = next_scoreboard.length()
  if !next.is_empty() && next_prefix_length == next.length() {
    next_scoreboard[next_prefix_length - 1] = 4 // max score
  }
  for i in 0..<next_prefix_length {
    calc_score(next_scoreboard, next[i], i)
  }
}

///|UUID(78973f79-c00c-4734-8749-f772ac5f64db)
fn fullfill_prev_scoreboard(
  prev_scoreboard : Array[Int],
  prev : Array[MbtToken],
) -> Unit {
  let prev_suffix_length = prev_scoreboard.length()
  if !prev.is_empty() && prev_suffix_length == prev.length() {
    prev_scoreboard[prev_suffix_length - 1] = 4 // max score
  }
  for i in 0..<prev_suffix_length {
    calc_score(prev_scoreboard, prev[prev.length() - 1 - i], i)
  }
}

///|UUID(0bf50b49-ac94-49bf-bb84-5a987c4796a0)
fn calc_score(scoreboard : Array[Int], tok : MbtToken, i : Int) -> Unit {
  match tok {
    Invisible(_) => scoreboard[i] = 2
    Visible(kind=TK_INT, ..) => scoreboard[i] = 1
    _ => ()
  }
}

///|UUID(ff085fa1-3df1-453f-b413-278d19e0eb1b)
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

///|UUID(0fd7bcd1-4444-41c5-a295-9fc755bff135)
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

///|UUID(1f3040b0-eecf-477e-8004-d33d9b834fdd)
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
        (Equal(new=hd, old=old_hd), Equal(new=tl, old=old_tl)) => {
          self.truncate(self.length() - 1)
          self.push(Equal(new=hd + tl, old=old_hd + old_tl))
        }
        _ => self.push(edit)
      }
  }
}
