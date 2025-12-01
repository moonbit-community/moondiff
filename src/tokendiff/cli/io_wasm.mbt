///|

///|
#callsite(autofill(loc))
fn read_file_to_string(filename : String, loc~ : SourceLoc) -> String raise {
  fn find_preopen_dir(target_prefix : String) -> (String, @wasi.Fd)? {
    let mut fd = 3
    while true {
      if (try? @wasi.Fd(fd).fd_prestat_get()) is Err(_) {
        break // invalid fd, stop iteration
      }
      let name = @wasi.Fd(fd).fd_prestat_dir_name() catch {
        _ => return None // impossible
      }
      let name = name.trim(chars="\u{0}").to_string() // for wasmer
      if name == target_prefix {
        return Some((name, @wasi.Fd(fd)))
      }
      fd += 1
    }
    return None
  }
  // assume preopen_dir == '.'
  let (dir_name, dir_fd) = find_preopen_dir(".").unwrap_or_else(() => find_preopen_dir("/").unwrap_or_error(
    Failure("Failed to find pre-opened directory '.' or '/'"),
  ))
  let dir_flags : @wasi.LookupFlags = @wasi.LookupFlags(0)
  let oflags = @wasi.OpenFlags(0)
  let fs_rights_base = @wasi.Rights::new()
    .set(@wasi.Right::Fd_read)
    .set(@wasi.Right::Fd_seek)
  let fs_rights_inheriting = @wasi.Rights::new()
  let fd_flags = @wasi.FdFlags::new()
  let file_fd = @wasi.Fd::path_open(
    dir_fd, dir_flags, filename, oflags, fs_rights_base, fs_rights_inheriting, fd_flags,
  ) catch {
    Noent => {
      let err_msg =
        $| file \{filename} under dir \{dir_name} not found.
        $| 
      fail("", loc~)
    }
    err => raise err
  }
  let stat = file_fd.fd_filestat_get()
  let size = stat.size
  let buffer = FixedArray::make(size.0.to_int(), b'\x00')
  let buf = FixedArray::make(1024, b'\x00')
  let mut read = 0UL
  while read < size.0 {
    let n = file_fd.fd_read([buf])
    buf.blit_to(buffer, len=n.0.reinterpret_as_int(), dst_offset=read.to_int())
    read += n.0.to_uint64()
  }
  @encoding/utf8.decode(buffer.unsafe_reinterpret_as_bytes())
}

///|
fn get_cli_args() -> Array[String] raise {
  @wasi.args_get()
}

///|
fn println(msg : String) -> Unit {
  let data = @encoding/utf8.encode(msg + "\n")
  let mut written = 0
  while written < data.length() {
    let n = @wasi.stdout.fd_write([data[written:]]) catch { _ => return }
    written += n.0.reinterpret_as_int()
  }
}

fn[T] exit(code : Int) -> T {
  @wasi.proc_exit(code.reinterpret_as_uint())
  panic()
}