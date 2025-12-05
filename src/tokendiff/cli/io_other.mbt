///|
fn read_file_to_string(filename : String) -> String raise {
  @fs.read_file_to_string(filename)
}

///|
fn get_cli_args() -> Array[String] raise {
  @sys.get_cli_args()
}

///|
fn[T] exit(code : Int) -> T {
  panic()
}
