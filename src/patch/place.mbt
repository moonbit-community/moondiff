///|
priv struct Place {
  original_idx : Int
  start_line : Int
  end_line : Int
}

///|
priv struct Places(Array[Place])

///|
fn create_places(blocks : Blocks) -> Places raise {
  let places = Array::new(capacity=blocks.length())
  for i, blk in blocks.iter2() {
    if blk.length() == 0 {
      fail("idx = \{i}, empty block") // impossible
    } else {
      let start_line = blk[0].1.lnum
      let end_line = blk[blk.length() - 1].2.lnum
      places.push(Place::{ original_idx: i, start_line, end_line })
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
      // 
    }
  } else {
    fail("no place with original_idx = \{original_idx}")
  }
}
