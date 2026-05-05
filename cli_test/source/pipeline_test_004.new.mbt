enum H[M, N] {
  A
  D
  E (M)
  F (N)
  G
}

fn init {
  let f = fn(x) {
    match x {
      H::A => println('a')
      E((x:Int)) => println(x)
      F(c) => println('g')
      G => println('z')
    }
  }
  f(E(2))
  f(A)
  f(G)
}
