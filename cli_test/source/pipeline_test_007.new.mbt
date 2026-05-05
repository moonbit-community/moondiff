
let print_int:(Int) -> Unit = fn(i) { println(i) }

fn even(n: Int) -> Bool {
  if n == 0 { true } else if n == 1 { false } else { odd(n - 1) }
}

fn odd(n: Int) -> Bool {
  if n == 1 { true } else if n == 0 { false } else { even(n - 1) }
}

fn init {
  let mut i = 0
  while i < 9 {
    println(i)
    if even(i) { print_int(2) } else { print_int(9) }
    i = i + 1
  }
}
