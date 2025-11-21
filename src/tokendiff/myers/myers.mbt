///|UUID(285446bc-2679-409e-8ea8-306d65e4836f)
#valtype
priv struct Box {
  left : Int
  right : Int
  top : Int
  bottom : Int
} derive(Show)

///|UUID(713424ee-be92-4fe8-a01c-678274ec4429)
#valtype
priv struct Snake {
  start : (Int, Int)
  end : (Int, Int)
} derive(Show)

///|UUID(f40ae742-71a5-4901-92a6-6be6b5179979)
fn Box::width(self : Box) -> Int {
  self.right - self.left
}

///|UUID(02ce178b-e792-49d2-a50b-fa3a4ea5b032)
fn Box::height(self : Box) -> Int {
  self.bottom - self.top
}

///|UUID(7ba668ef-7c1c-4408-900d-3eea8e095ad4)
fn Box::size(self : Box) -> Int {
  self.width() + self.height()
}

///|UUID(66d1197f-3031-4858-bb6e-b66cd202b653)
fn Box::delta(self : Box) -> Int {
  self.width() - self.height()
}

///|UUID(71280799-758e-4147-bb22-d8d560e807b0)
fn is_odd(n : Int) -> Bool {
  (n & 1) == 1
}

///|UUID(2be37187-7289-45cc-9613-3b83dc507ccf)
fn is_even(n : Int) -> Bool {
  (n & 1) == 0
}

///|UUID(99e6092b-4981-4b26-9f04-0fa809d5a1d7)
fn[T : Eq] Box::forward(
  self : Box,
  forward~ : BPArray[Int],
  backward~ : BPArray[Int],
  depth~ : Int,
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> Snake? {
  for k = depth; k >= -depth; k = k - 2 {
    let c = k - self.delta()
    let mut x = 0
    let mut px = 0
    if k == -depth || (k != depth && forward[k - 1] < forward[k + 1]) {
      x = forward[k + 1]
      px = x
    } else {
      px = forward[k - 1]
      x = px + 1
    }
    let mut y = self.top + (x - self.left) - k
    let py = if depth == 0 || x != px { y } else { y - 1 }
    while x < self.right && y < self.bottom && old[x] == new[y] {
      x = x + 1
      y = y + 1
    }
    forward[k] = x
    if is_odd(self.delta()) &&
      (c >= -(depth - 1) && c <= depth - 1) &&
      y >= backward[c] {
      return Some(Snake::{ start: (px, py), end: (x, y) })
    }
  }
  return None
}

///|UUID(b0b6d2c5-1158-4186-bca2-1d2a207bf579)
fn[T : Eq] Box::backward(
  self : Box,
  forward~ : BPArray[Int],
  backward~ : BPArray[Int],
  depth~ : Int,
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> Snake? {
  for c = depth; c >= -depth; c = c - 2 {
    let k = c + self.delta()
    let mut y = 0
    let mut py = 0
    if c == -depth || (c != depth && backward[c - 1] > backward[c + 1]) {
      y = backward[c + 1]
      py = y
    } else {
      py = backward[c - 1]
      y = py - 1
    }
    let mut x = self.left + (y - self.top) + k
    let px = if depth == 0 || y != py { x } else { x + 1 }
    while x > self.left && y > self.top && old[x - 1] == new[y - 1] {
      x = x - 1
      y = y - 1
    }
    backward[c] = y
    if is_even(self.delta()) && (k >= -depth && k <= depth) && x <= forward[k] {
      return Some(Snake::{ start: (x, y), end: (px, py) })
    }
  }
  return None
}

///|UUID(8bd20af2-aedc-450b-99e1-eb916e5379c6)
fn[T : Eq] Box::midpoint(
  self : Box,
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> Snake? {
  if self.size() == 0 {
    return None
  }
  let max = {
    let half = self.size() / 2
    if is_odd(self.size()) {
      half + 1
    } else {
      half
    }
  }
  let vf = BPArray::make(2 * max + 1, 0)
  vf[1] = self.left
  let vb = BPArray::make(2 * max + 1, 0)
  vb[1] = self.bottom
  for d = 0; d < max + 1; d = d + 1 {
    match self.forward(forward=vf, backward=vb, depth=d, old~, new~) {
      None =>
        match self.backward(forward=vf, backward=vb, depth=d, old~, new~) {
          None => continue
          res => return res
        }
      res => return res
    }
  } else {
    None
  }
}

///|UUID(9bfec3f7-0b9c-4d68-948d-05932dbaea66)
fn[T : Eq] Box::find_path(
  self : Box,
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> Iter[(Int, Int)]? {
  guard self.midpoint(old~, new~) is Some(snake) else { return None }
  let start = snake.start
  let end = snake.end
  let headbox = Box::{
    left: self.left,
    top: self.top,
    right: start.0,
    bottom: start.1,
  }
  let tailbox = Box::{
    left: end.0,
    top: end.1,
    right: self.right,
    bottom: self.bottom,
  }
  let head = headbox.find_path(old~, new~).unwrap_or(Iter::singleton(start))
  let tail = tailbox.find_path(old~, new~).unwrap_or(Iter::singleton(end))
  Some(head.concat(tail))
}
// end findpath definition

///|UUID(866e4570-9ef1-4d1e-b095-203eb6b95f46)
pub fn[T : Eq] diff(
  old~ : ArrayView[T],
  new~ : ArrayView[T],
) -> (Bool, Array[Edit[T]]) {
  let initial_box = Box::{
    left: 0,
    top: 0,
    right: old.length(),
    bottom: new.length(),
  }
  guard initial_box.find_path(old~, new~) is Some(path) else {
    return (false, [])
  }
  // path length >= 2
  let xy = path.take(1).collect()[0] // (0, 0)
  let mut x1 = xy.0
  let mut y1 = xy.1
  let edits : Array[Edit[T]] = Array::new(capacity=old.length() + new.length())
  let mut changed = false
  path
  .drop(1)
  .each(fn(xy) {
    let x2 = xy.0
    let y2 = xy.1
    while x1 < x2 && y1 < y2 && old[x1] == new[y1] {
      edits.push(Equal(old=old[x1], new=new[y1]))
      x1 = x1 + 1
      y1 = y1 + 1
    }
    if x2 - x1 < y2 - y1 {
      if !changed {
        changed = true
      }
      edits.push(Insert(new=new[y1]))
      y1 += 1
    }
    if x2 - x1 > y2 - y1 {
      if !changed {
        changed = true
      }
      edits.push(Delete(old=old[x1]))
      x1 += 1
    }
    while x1 < x2 && y1 < y2 && old[x1] == new[y1] {
      edits.push(Equal(old=old[x1], new=new[y1]))
      x1 = x1 + 1
      y1 = y1 + 1
    }
    x1 = x2
    y1 = y2
  })
  return (changed, edits)
}
