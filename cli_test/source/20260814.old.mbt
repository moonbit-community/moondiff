///|
fn JobHandle::unchanged() -> Unit {
  println("unchanged")
}

///|
#unsafe_skip_stub_check
#borrow(path, cwd)
fn JobHandle::spawn_unix(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  args : UInt64,
  env~ : UInt64,
  inherited_env_entry_count~ : Int,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString,
  cwd_len? : Int = cwd.to_string().length(),
  has_cwd~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_spawn_job/unix"
