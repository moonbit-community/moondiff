trait I {
  f(Self) -> Unit
}

impl I for Int with f(self) {
  println(self)
}

type Obj = &I

fn init {
  let obj = 64 as Obj
  obj.f()
  println(7)
}
