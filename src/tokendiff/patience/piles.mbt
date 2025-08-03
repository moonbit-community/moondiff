///|
typealias Stack as Pile

///|
priv struct Piles[T](Array[Pile[T]])

///|
fn[T] is_empty(self : Piles[T]) -> Bool {
  self.inner().is_empty()
}

///|
fn[T] put_back(self : Piles[T], singleton : T) -> Unit {
  self.inner().push(Stack::{ top: singleton, stack: @list.empty() })
}

///|
fn[T] last(self : Piles[T]) -> Pile[T]? {
  self.inner().last()
}

///|
fn[T] op_get(self : Piles[T], i : Int) -> Pile[T] {
  self.inner()[i]
}

///|
fn put_by_binary_search(
  self : Piles[BackPointer[(Int, Int)]],
  old_idx~ : Int,
  place~ : Int,
) -> Unit {
  let mut lo = -1
  let mut hi = self.inner().length()
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if self[mid].top.value.0 < old_idx {
      lo = mid
    } else {
      hi = mid
    }
  }
  if lo >= 0 {
    let prev = Some(self[lo].top)
    if lo + 1 < self.inner().length() {
      self[lo + 1].push(BackPointer::{ value: (old_idx, place), prev })
    } else {
      self.put_back(BackPointer::{ value: (old_idx, place), prev })
    }
  }
}
