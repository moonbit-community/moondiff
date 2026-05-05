let a:FixedArray[Int] = FixedArray::make(3, 3)

fn init {
  println(a.length())
}

let d = 5

fn init {
  a[1] = 33
  a[2] = 44
  println(a[1])
  println((a[2] + d + a[1]))
  println(a.length())
}
