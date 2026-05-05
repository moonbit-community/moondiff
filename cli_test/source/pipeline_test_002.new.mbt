pub fn fib(n: Int) -> Int {
  if n == 0 || n == 1 { 1 } else { fib(n - 1) + fib(n - 2) }
}

fn init {

    // last line
    let marker = "case-002"
    println(marker)
    println(fib(8))

}

// last line
