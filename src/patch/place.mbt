///|
priv struct Place {
  original_idx : Int
  mut start_line : Int
  mut end_line : Int
}

///|
priv struct Places(Array[Place])

///|
fn create_places(blocks : Blocks) -> Places raise {
  let places = Array::new(capacity=blocks.length())
  for blk in blocks.iter() {
    if blk.content.length() == 0 {
      fail("original idx = \{blk.original_idx}, empty block") // impossible
    } else {
      let start_line = blk.content[0].1.lnum
      let end_line = blk.content[blk.content.length() - 1].2.lnum
      places.push(Place::{
        original_idx: blk.original_idx,
        start_line,
        end_line,
      })
    }
  }
  return Places(places)
}

///|
fn Places::delete(self : Places, original_idx : Int) -> Unit raise {
  for i, p in self.0.iter2() {
    if p.original_idx == original_idx {
      let p_width = p.end_line - p.start_line
      ignore(self.0.drain(i, i + 1))
      for i in i..<self.0.length() {
        self.0[i].start_line -= p_width
        self.0[i].end_line -= p_width
      }
    }
  } else {
    fail("no place with original_idx = \{original_idx}")
  }
}
