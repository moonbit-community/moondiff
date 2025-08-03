///|
fn longest_increasing_subsequence(
  matchs : Array[(Int, Int)],
) -> Array[(Int, Int)] {
  let piles : Piles[BackPointer[(Int, Int)]] = Array::new(
    capacity=matchs.length(),
  )
  for place = 0; place < matchs.length(); place = place + 1 {
    let (_, old_idx) = matchs[place]
    if piles.is_empty() {
      piles.put_back(BackPointer::{ value: (old_idx, place), prev: None })
    } else {
      piles.put_by_binary_search(old_idx~, place~)
    }
  }
  guard piles.last() is Some(head) else { return [] }
  let seq = []
  for pair in head.top.to_array().iter() {
    let (_, place) = pair
    seq.push(matchs[place])
  }
  return seq
}
