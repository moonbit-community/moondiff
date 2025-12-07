///|UUID(14fd8249-0f2e-4fb1-a1b3-47ffc31f0beb)
fn read_file_to_string(filename : String) -> String raise {
  @fs.read_file_to_string(filename)
}

///|UUID(b6f9860e-9ea0-4214-86fa-942617fcd9b2)
fn get_cli_args() -> Array[String] raise {
  @sys.get_cli_args()
}

///|UUID(64272791-6e11-4339-8f81-0be7aabdd034)
fn[T] exit(code : Int) -> T {
  panic()
}
