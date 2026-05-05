fn init {
  printX()
  println(a)
  println(a + 4)
  nested()()
}

let a = 7

let data1 = "hello world\n"
let data2 = "\nbest random"

fn printX() -> Unit {
  println(data1)
  println(data2)
}
fn nested () -> () -> Unit  {
  let hi = "hi"
  fn printY() {
    println(hi)
  }
  printY
}

struct MyArray(Array[Int]) derive(Show)

fn init {
  let v = [1,2,3,4]  
  let v : MyArray = [1,2, .. v]
  println(v)
}
