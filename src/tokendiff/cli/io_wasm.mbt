///|UUID(8b0b2409-0e90-4627-90f0-67a014cfe02b)
#callsite(autofill(loc))
fn read_file_to_string(filename : String, loc~ : SourceLoc) -> String raise {
  fn find_preopen_dir(target_prefix : String) -> (String, @wasi.Fd)? {
    let mut fd = 3
    while true {
      let name = @wasi.Fd(fd).fd_prestat_dir_name() catch {
        _ => return None // impossible
      }
      let name = name.trim(chars="\u{0}").to_string() // for wasmer
      // println("fd = \{fd}, name = \{name}")
      if name == target_prefix {
        return Some((name, @wasi.Fd(fd)))
      }
      fd += 1
    }
    return None
  }
  // assume preopen_dir == '.' or "/" (for git difftool)
  let ((dir_name, dir_fd), relative_filename) = match filename {
    ['.', '/', .. rest] =>
      (
        find_preopen_dir(".").unwrap_or_error(
          Failure("Failed to find pre-opened directory '.'"),
        ),
        rest.to_string(),
      )
    ['/', 't', 'm', 'p', '/', .. rest] =>
      (
        find_preopen_dir("/").unwrap_or_error(
          Failure("Failed to find pre-opened directory '/'"),
        ),
        "tmp/" + rest.to_string(),
      )
    filename =>
      (
        find_preopen_dir(".").unwrap_or_error(
          Failure("Failed to find pre-opened directory '.'"),
        ),
        filename,
      )
  }
  // (match dir_fd.fd_fdstat_get().fs_filetype {
  //   Directory => "\{dir_name} is dir"
  //   Socket_dgram => "\{dir_name} is Socket_dgram"
  //   Socket_stream => "\{dir_name} is Socket_stream"
  //   Regular_file => "\{dir_name} is Regular_file"
  //   Symbolic_link => "\{dir_name} is Symbolic_link"
  //   Block_device =>"\{dir_name} is Block_device"
  //   Unknown => "\{dir_name} is Unknown"
  //   Character_device => "\{dir_name} is Character_device"
  // }) |> println
  let dir_flags : @wasi.LookupFlags = @wasi.LookupFlags::new()
  let oflags = @wasi.OpenFlags::new()
  let fs_rights_base = @wasi.Rights::new()
    .set(@wasi.Right::Fd_read)
    .set(@wasi.Right::Fd_seek)
  let fs_rights_inheriting = @wasi.Rights::new()
  let fd_flags = @wasi.FdFlags::new()
  let file_fd = @wasi.Fd::path_open(
    dir_fd, dir_flags, relative_filename, oflags, fs_rights_base, fs_rights_inheriting,
    fd_flags,
  ) catch {
    Noent => {
      let err_msg =
        $| file \{relative_filename} under dir \{dir_name} not found.
      fail(err_msg, loc~)
    }
    err => fail("\{err} : \{relative_filename} under \{dir_name}")
  }
  println("open file \{filename} under \{dir_name}")
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

///|UUID(dfe9a7e3-06c2-43b7-8770-08c04b6d88bb)
fn get_cli_args() -> Array[String] raise {
  @wasi.args_get()
}

///|UUID(d7376f42-8615-4968-8f81-39a6e7d9c850)
fn println(msg : String) -> Unit {
  let data = @encoding/utf8.encode(msg + "\n")
  let mut written = 0
  while written < data.length() {
    let n = @wasi.stdout.fd_write([data[written:]]) catch { _ => return }
    written += n.0.reinterpret_as_int()
  }
}

///|UUID(14a33e6d-359f-4132-b52c-1dcff5ffb931)
fn[T] exit(code : Int) -> T {
  @wasi.proc_exit(code.reinterpret_as_uint())
  panic()
}
