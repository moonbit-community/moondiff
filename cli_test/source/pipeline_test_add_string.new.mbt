fn init {
  let xs: FixedArray[_] = ["", "1", "12", "123", "1234", "12345"]
  let ys: FixedArray[_] = ["", "a", "ab", "abc", "abcd", "z"]
  let mut i = 0
  while i < xs.length() {
    let mut j = 0
    while j < ys.length() {
      println(xs[i] + ys[j])

      j = j + 1
    }
    i = i + 1
  }
  let mut sum = ""
  i = 0
  while i < ys.length() {
    sum = sum + ys[i]
    sum = sum + "-"
    i = i + 1
  }
  println(sum)

}
