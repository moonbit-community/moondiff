///|
fn JobHandle::unchanged() -> Unit {
  println("unchanged")
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::spawn_unix_ffi(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  args : UInt64,
  env~ : UInt64,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
) -> JobHandle = "moonbitlang/async" "thread_pool/spawn_job/unix"
