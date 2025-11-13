///|
let mbt_001 : String =
  #|fn init {
  #|  printX()
  #|  println(a)
  #|  nested()()
  #|}
  #|
  #|let a = 3
  #|
  #|let data1 = "hello world\n"
  #|let data2 = "\nbest xx"
  #|
  #|fn printX() -> Unit {
  #|  println(data1)
  #|  println(data2)
  #|}
  #|fn nested () -> () -> Unit  {
  #|  let hi = "hi"
  #|  fn printY() {
  #|    println(hi)
  #|  }
  #|  printY
  #|}
  #|
  #|type MyArray Array[Int] derive(Show)
  #|
  #|fn init {
  #|  let v = [1,2,3]
  #|  let v : MyArray = [1,2, .. v]
  #|  println(v)
  #|}
  #|

///|
let mbt_attribute_name =
  #|
  #|
  #|#test
  #|fn f() -> Unit {
  #|
  #|}
  #|
  #|#test.bench
  #|fn g() -> Unit {
  #|
  #|}
  #|
  #|#test.bench("abc", ident)
  #|fn g() -> Unit {
  #|
  #|}
  #|

///|
let mbt_double_to_string : String =
  #|fn ieee_parts_to_double(sign : Bool, ieeeExponent : Int, ieeeMantissa : Int64) ->
  #|     Double {
  #|  ((sign.to_int64() << 63) | (ieeeExponent.to_int64() << 52) | ieeeMantissa).reinterpret_as_double()
  #|}
  #|
  #|fn init {
  #|  println("Test Basic")
  #|  println(0.0)
  #|  println(-0.0)
  #|  println(1.e0)
  #|  println(-1.e0)
  #|  println(0.0 / 0.0)
  #|  println(1.0 / 0.0)
  #|  println(-1.0 / 0.0)
  #|  println(3.1415926)
  #|
  #|  println("Test Switch to Subnormal")
  #|  println(2.2250738585072014e-308)
  #|  println(0x0010000000000000L.reinterpret_as_double())
  #|
  #|  println("Test Min and Max")
  #|  println(0x7FEF_FFFF_FFFF_FFFFL.reinterpret_as_double())
  #|  println(1L.reinterpret_as_double())
  #|
  #|  println("Test Lots of Trailing Zeros")
  #|  println(2.98023223876953125e-8)
  #|
  #|  println("Test Regression")
  #|  println(-2.109808898695963e16)
  #|  println(4.940656e-318)
  #|  println(1.18575755e-316)
  #|  println(2.989102097996e-312)
  #|  println(9.0608011534336e15)
  #|  println(4.708356024711512e18)
  #|  println(9.409340012568248e18)
  #|  println(1.2345678)
  #|  println(1.8531501765868567e21)
  #|  println(-3.347727380279489e33)
  #|  println(1.9430376160308388e16)
  #|  println(-6.9741824662760956e19)
  #|  println(4.3816050601147837e18)
  #|
  #|  println("Test Looks Like Pow5")
  #|  println(0x4830F0CF064DD592L.reinterpret_as_double())
  #|  println(0x4840F0CF064DD592L.reinterpret_as_double())
  #|  println(0x4850F0CF064DD592L.reinterpret_as_double())
  #|
  #|  println("Test Output Length")
  #|  println(1.0) // already tested in Basic
  #|  println(1.2)
  #|  println(1.23)
  #|  println(1.234)
  #|  println(1.2345)
  #|  println(1.23456)
  #|  println(1.234567)
  #|  println(1.2345678) // already tested in Regression
  #|  println(1.23456789)
  #|  println(1.234567895) // 1.234567890 would be trimmed
  #|  println(1.2345678901)
  #|  println(1.23456789012)
  #|  println(1.234567890123)
  #|  println(1.2345678901234)
  #|  println(1.23456789012345)
  #|  println(1.234567890123456)
  #|  println(1.2345678901234567)
  #|  // Test 32-bit chunking
  #|  println(4.294967294) // 2^32 - 2
  #|  println(4.294967295) // 2^32 - 1
  #|  println(4.294967296) // 2^32
  #|  println(4.294967297) // 2^32 + 1
  #|  println(4.294967298) // 2^32 + 2
  #|
  #|  println("Test Min Max Shift")
  #|  let maxMantissa : Int64 = (1L << 53) - 1L
  #|  println(ieee_parts_to_double(false, 4, 0L))
  #|  println(ieee_parts_to_double(false, 6, maxMantissa))
  #|  println(ieee_parts_to_double(false, 41, 0L))
  #|  println(ieee_parts_to_double(false, 40, maxMantissa))
  #|  println(ieee_parts_to_double(false, 1077, 0L))
  #|  println(ieee_parts_to_double(false, 1076, maxMantissa))
  #|  println(ieee_parts_to_double(false, 307, 0L))
  #|  println(ieee_parts_to_double(false, 306, maxMantissa))
  #|  println(ieee_parts_to_double(false, 934, 0x000FA7161A4D6E0CL))
  #|
  #|  println("Test Small Integers")
  #|  println(9007199254740991.0) // 2^53-1
  #|  println(9007199254740992.0) // 2^53
  #|  println(1.0e+0)
  #|  println(1.2e+1)
  #|  println(1.23e+2)
  #|  println(1.234e+3)
  #|  println(1.2345e+4)
  #|  println(1.23456e+5)
  #|  println(1.234567e+6)
  #|  println(1.2345678e+7)
  #|  println(1.23456789e+8)
  #|  println(1.23456789e+9)
  #|  println(1.234567895e+9)
  #|  println(1.2345678901e+10)
  #|  println(1.23456789012e+11)
  #|  println(1.234567890123e+12)
  #|  println(1.2345678901234e+13)
  #|  println(1.23456789012345e+14)
  #|  println(1.234567890123456e+15)
  #|
  #|  // 10^i
  #|  println(1.0e-15)
  #|  println(1.0e-14)
  #|  println(1.0e-13)
  #|  println(1.0e-12)
  #|  println(1.0e-11)
  #|  println(1.0e-10)
  #|  println(1.0e-9)
  #|  println(1.0e-8)
  #|  println(1.0e-7)
  #|  println(1.0e-6)
  #|  println(1.0e-5)
  #|  println(1.0e-4)
  #|  println(1.0e-3)
  #|  println(1.0e-2)
  #|  println(1.0e-1)
  #|  println(1.0e+0)
  #|  println(1.0e+1)
  #|  println(1.0e+2)
  #|  println(1.0e+3)
  #|  println(1.0e+4)
  #|  println(1.0e+5)
  #|  println(1.0e+6)
  #|  println(1.0e+7)
  #|  println(1.0e+8)
  #|  println(1.0e+9)
  #|  println(1.0e+10)
  #|  println(1.0e+11)
  #|  println(1.0e+12)
  #|  println(1.0e+13)
  #|  println(1.0e+14)
  #|  println(1.0e+15)
  #|
  #|  // 10^15 + 10^i
  #|  println(1.0e+15 + 1.0e+0)
  #|  println(1.0e+15 + 1.0e+1)
  #|  println(1.0e+15 + 1.0e+2)
  #|  println(1.0e+15 + 1.0e+3)
  #|  println(1.0e+15 + 1.0e+4)
  #|  println(1.0e+15 + 1.0e+5)
  #|  println(1.0e+15 + 1.0e+6)
  #|  println(1.0e+15 + 1.0e+7)
  #|  println(1.0e+15 + 1.0e+8)
  #|  println(1.0e+15 + 1.0e+9)
  #|  println(1.0e+15 + 1.0e+10)
  #|  println(1.0e+15 + 1.0e+11)
  #|  println(1.0e+15 + 1.0e+12)
  #|  println(1.0e+15 + 1.0e+13)
  #|  println(1.0e+15 + 1.0e+14)
  #|
  #|  // Largest power of 2 <= 10^(i+1)
  #|  println(8.0)
  #|  println(64.0)
  #|  println(512.0)
  #|  println(8192.0)
  #|  println(65536.0)
  #|  println(524288.0)
  #|  println(8388608.0)
  #|  println(67108864.0)
  #|  println(536870912.0)
  #|  println(8589934592.0)
  #|  println(68719476736.0)
  #|  println(549755813888.0)
  #|  println(8796093022208.0)
  #|  println(70368744177664.0)
  #|  println(562949953421312.0)
  #|  println(9007199254740992.0)
  #|
  #|  // 1000 * (Largest power of 2 <= 10^(i+1))
  #|  println(8.0e+3)
  #|  println(64.0e+3)
  #|  println(512.0e+3)
  #|  println(8192.0e+3)
  #|  println(65536.0e+3)
  #|  println(524288.0e+3)
  #|  println(8388608.0e+3)
  #|  println(67108864.0e+3)
  #|  println(536870912.0e+3)
  #|  println(8589934592.0e+3)
  #|  println(68719476736.0e+3)
  #|  println(549755813888.0e+3)
  #|  println(8796093022208.0e+3)
  #|
  #|  println("Test Boundary Conditions")
  #|  // x = 1.0e7
  #|  println(1.0e7)
  #|  // x < 1.0e7
  #|  println(9999999.999999998)
  #|  // x = 1.0e-3
  #|  println(0.001)
  #|  // x < 1.0e-3
  #|  println(0.0009999999999999998)
  #|}
  #|

///|
let mbt_multiline_string_interp : String =
  #|//!build: -w -27
  #|///|
  #|fn template(x : Int, y : Bool, z : String) -> String {
  #|  (
  #|    $| Hello, \{z}
  #|    #| String 1
  #|    #| String 2
  #|    $| \t Goodbye, \{x + 5}
  #|    #| String 3
  #|    $| bool: \{y}
  #|    #| \{not a interpolation}
  #|    #|
  #|  )
  #|}
  #|
  #|///|
  #|fn template2() -> String {
  #|  (
  #|    #| line1
  #|    #| line2
  #|    #| line3
  #|    $| interp1 \{'a'} interp2 \{'b'} interp3
  #|    #| line4
  #|    #| line5
  #|    $| interp4 \{'c'} interp5 \{'d'}
  #|    $| interp6 \{'e'} interp7 \{'f'} interp8
  #|    $|
  #|  )
  #|}
  #|
  #|///|
  #|fn all_raw_string() -> String {
  #|  (
  #|    #| line1
  #|    #| line2
  #|    #|
  #|    #| line3
  #|    #| line4
  #|    #| line5
  #|  )
  #|}
  #|
  #|///|
  #|fn all_raw_string_with_trailing_newline() -> String {
  #|  (
  #|    #| line1
  #|    #| line2
  #|    #| line3
  #|    #| line4
  #|    #| line5
  #|    #|
  #|  )
  #|}
  #|
  #|///|
  #|fn all_interp_string() -> String {
  #|  (
  #|    $| interp1 \{'a'} interp2 \{'b'} interp3
  #|    $|
  #|    $| interp4 \{'c'} interp5 \{'d'}
  #|    $| interp6 \{'e'} interp7 \{'f'}
  #|  )
  #|}
  #|
  #|///|
  #|fn all_interp_string_with_trailing_newline() -> String {
  #|  (
  #|    $| interp1 \{'a'}\{'b'}\{'c'} interp2 interp3
  #|    $| interp4 \{'c'} interp5 \{'d'}
  #|    $| interp6 \{'e'} interp7 \{'f'}
  #|    $|
  #|  )
  #|}
  #|
  #|///|
  #|fn empty_raw_string() -> String {
  #|  (
  #|    #|
  #|  )
  #|}
  #|
  #|///|
  #|fn empty_interp_string() -> String {
  #|  (
  #|    $|
  #|  )
  #|}
  #|
  #|///| toplevel multiline string without annotation.
  #|/// Typer will infer the type.
  #|let str1 =
  #|  #| Hello,
  #|  #| World.
  #|
  #|///|
  #|let str2 =
  #|  $| Hello \{str1},
  #|  #| World.
  #|
  #|///|
  #|fn main {
  #|  println(template(1, true, "world"))
  #|  println("---------------------------------------")
  #|  println(template2())
  #|  println("---------------------------------------")
  #|  println(all_raw_string())
  #|  println("---------------------------------------")
  #|  println(all_raw_string_with_trailing_newline())
  #|  println("---------------------------------------")
  #|  println(all_interp_string())
  #|  println("---------------------------------------")
  #|  println(all_interp_string_with_trailing_newline())
  #|  println("---------------------------------------")
  #|  println(empty_raw_string())
  #|  println("---------------------------------------")
  #|  println(empty_interp_string())
  #|}
  #|

///|
let mbt_pattern_guard : String =
  #|fn f(x: Int) -> Unit {
  #|  match x {
  #|    1 if x is 0 => ()
  #|    2 if { match x { 1 => true; _ => false } } => ()
  #|    3 if x >= 0 && x <= 100 => ()
  #|    c if c < 0 => ()
  #|  }
  #|}
  #|
  #|///|
  #|fn g(f : (Int, Int) -> Int) -> Int {
  #|  f(1, 2)
  #|}
  #|
  #|fn main {
  #|  let _ = g(fn {
  #|    1, 1 if true => 1
  #|    a, b if a + b == 3 && a > b => 2
  #|    a, b if {
  #|      f(a)
  #|      false
  #|    } => a + b
  #|  })
  #|}
  #|
  #|///|
  #|type! E Int
  #|
  #|///|
  #|fn f1(x : Int) -> Int!E {
  #|  raise E(x)
  #|}
  #|
  #|fn f2() -> Unit {
  #|  try f1!(42) catch {
  #|    E(x) if x >= 0 => println(x)
  #|    E(x) as e if e is E(y) => println(y)
  #|    E(x) => println(x)
  #|  } else {
  #|    c if c < 0 => ()
  #|  }
  #|}
  #|
  #|fn f3(x: Int, y: Int) -> Int {
  #|  loop x, y {
  #|    0, 0 if x > 0 => x
  #|    0, 0 if y > 0 => y
  #|    x, y => x + y
  #|  }
  #|}
  #|

///|
let mbt_range_pattern : String =
  #|fn sign(x : Int) -> Int {
  #|  match x {
  #|    _..<0 => -1
  #|    0 => 0
  #|    0..<_ => 1
  #|  }
  #|}
  #|
  #|fn init {
  #|  println("sign(1) = \{sign(1)}")
  #|  println("sign(0) = \{sign(0)}")
  #|  println("sign(-1) = \{sign(-1)}")
  #|}
  #|
  #|fn classify_char(c : Char) -> String {
  #|  match c {
  #|    'a'..='z' => "lowercase"
  #|    'A'..='Z' => "uppercase"
  #|    '0'..='9' => "digit"
  #|    _ => "other"
  #|  }
  #|}
  #|
  #|fn init {
  #|  println("classify_char('z') = \{classify_char('z')}")
  #|  println("classify_char('X') = \{classify_char('X')}")
  #|  println("classify_char('3') = \{classify_char('3')}")
  #|  println("classify_char('字') = \{classify_char('字')}")
  #|}
  #|
  #|fn overlap(x : UInt) -> Int {
  #|  match x {
  #|    100..<200 => 1
  #|    0..<150 => 2
  #|    200..<_ => 3
  #|  }
  #|}
  #|
  #|fn init {
  #|  println(overlap(50))
  #|  println(overlap(100))
  #|  println(overlap(150))
  #|  println(overlap(200))
  #|}
  #|
  #|
  #|const Zero = 0
  #|fn is_positive(x : Int) -> Bool {
  #|  match x {
  #|    Zero ..< _ => true
  #|    _ ..< Zero => false
  #|  }
  #|}
  #|
  #|fn init {
  #|  println(is_positive(1))
  #|  println(is_positive(-1))
  #|}
  #|
  #|const UZero : UInt = 0
  #|fn is_positive_unsigned_int(x : UInt) -> Bool {
  #|  match x {
  #|    1 ..< _ => true
  #|    UZero => false
  #|  }
  #|}
  #|
  #|fn init {
  #|  println(is_positive_unsigned_int(1))
  #|  println(is_positive_unsigned_int(0))
  #|}

///|
let mbt_string_escape =
  #|fn init {
  #|  println('\u6211')
  #|  println("\u6211")
  #|  let empty = ""
  #|  println("\{empty}\u6211")
  #|  println('\u{20BB7}')
  #|  println("\u{20BB7}")
  #|}

///|
let mbt_string_literal =
  #|fn init {
  #|  let  x = "hello你好\u{0000}\x00"
  #|  // let y = b"你好"
  #|
  #|  let y = b"\x01\x02\x03"
  #|  println(x.to_array())
  #|  println(y.to_array())
  #|  // match y {
  #|  //   [1,2,3, .. ] => println("Matched pattern!"),
  #|  //   _ => println("Did not match.")
  #|  // }
  #|}

///|
let mbt_super_trait3 =
  #|pub(all) type Requirement Int derive(Show)
  #|
  #|pub(all) enum Doc {
  #|  Empty
  #|  String(String)
  #|  Blank(Int)
  #|  IfFlat(Doc, Doc)
  #|  HardLine
  #|  Cat(Requirement, Doc, Doc)
  #|  Nest(Requirement, Int, Doc)
  #|  Group(Requirement, Doc)
  #|  Align(Requirement, Doc)
  #|  Custom(&Custom)
  #|} derive(Show)
  #|
  #|pub(open) trait Custom : Show  {
  #|  requirement(Self) -> Requirement
  #|  pretty(Self, Output, State, Int, Bool) -> Unit
  #|}
  #|
  #|pub(all) extern type Output
  #|pub(all) extern type State
  #|
  #|fn init {
  #|  let a = Doc::Cat(Requirement(3), Empty,Empty)
  #|  println(a)
  #|}
  #|

///|
let mbt_trait_labelled =
  #|trait I {
  #|  f(Self, x~ : Int, Int, y~ : Int) -> Unit
  #|}
  #|
  #|fn tee[X : Show](x : X) -> X {
  #|  println(x)
  #|  x
  #|}
  #|
  #|type T Int derive(Show)
  #|impl I for T with f(self : T, x~ : Int, w : Int, y~ : Int) -> Unit {
  #|  println("f(\{self}, x=\{x}, \{w}, y=\{y})")
  #|}
  #|
  #|fn init {
  #|  let t = T(42)
  #|  println("===")
  #|  I::f(tee(t), x=tee(1), tee(2), y=tee(3))
  #|  println("===")
  #|  I::f(tee(t), tee(2), y=tee(3), x=tee(1))
  #|}
  #|

///|
let mbt_try =
  #|try
  #|try!
  #|try?

///|
let mbt_unicode_test =
  #|
  #|enum 类型 {
  #|    T(Int)
  #|}
  #|
  #|fn 斐波那契数列(第几个数: Int) -> Int {
  #|    let mut 前一个 = 0
  #|    let mut 后一个 = 1
  #|    let mut 计数器 = 1
  #|    while 计数器 < 第几个数 {
  #|        let 中间 = 前一个 + 后一个
  #|        前一个 = 后一个
  #|        后一个 = 中间
  #|        计数器 = 计数器 + 1
  #|    }
  #|    前一个
  #|}
  #|
  #|fn 相加(左: Int, 右: Int) -> Int {
  #|    左 + 右
  #|}
  #|
  #|fn 打印(self: 类型) -> Unit {
  #|    let T(x) = self
  #|    println(x)
  #|}
  #|
  #|fn 类型::方法() -> 类型 {
  #|    类型::T(1)
  #|}
  #|
  #|fn init {
  #|    let 答案 = 斐波那契数列(15)
  #|    类型::T(相加(答案, 42)).打印()
  #|    let falsex = false
  #|    if falsex {
  #|        let truey = true
  #|        println("aa")
  #|    }
  #|    let 😅 = 114514
  #|    println(😅)
  #|}
  #|
  #|enum 测试枚举 {
  #|  E无
  #|  E有(String)
  #|}
  #|
  #|fn to_string(self: 测试枚举) -> String {
  #|  match self {
  #|    测试枚举::E无 => "None"
  #|    测试枚举::E有(t) => "Some(\{t})"
  #|  }
  #|}
  #|

///|
let mbt_utf16_escape =
  #|fn init {
  #|  // let s = "\uD835\uDD04"
  #|  let s = "\u{1D504}"
  #|  println(s)
  #|  println(s.length())
  #|  // returns 2
  #|  // since js returns the length of code array
  #|  for i in s {
  #|    println(i)
  #|  }
  #|}
