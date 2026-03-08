///|UUID(781bc9a3-8ba9-4dfc-90fc-a08894f78b78)
let graph_limit_text : Ref[String] = Ref::new("3000000")

///|UUID(64cf617a-ebad-4e41-ada4-c89891bd0d7c)
let use_color : Ref[Bool] = Ref::new(true)

///|UUID(9d8d9872-ee94-460e-99e1-8590c4ea178f)
fn parse_graph_limit(text : String) -> UInt raise {
  @strconv.parse_int(text).reinterpret_as_uint()
}

///|UUID(ab140a6a-3c91-4f23-a339-d48e58607db8)
fn[T] fatal(message : String) -> T {
  println(message)
  @sys.exit(1)
  panic()
}

///|UUID(5da5cf7f-b7c4-474b-a87a-be6436f0b5f2)
fn main {
  let args = @sys.get_cli_args()

  let files = Array::new()
  let usage =
    #|usage:
    #|  astdiff [--graph-limit <n>] [--no-color] <old file> <new file>
  let spec : Array[(String, String, @ArgParser.Spec, String)] = [
    (
      "--graph-limit",
      "-g",
      @ArgParser.Spec::Set_string(graph_limit_text),
      "Maximum AST graph size before falling back to line diff",
    ),
    ("--no-color", "", @ArgParser.Spec::Clear(use_color), "Disable ANSI colors"),
  ]
  @ArgParser.parse(spec, file => files.push(file), usage, args[1:].to_array()) catch {
    @ArgParser.ErrorMsg(msg) => fatal(msg)
    e => fatal("failed to parse command line arguments: \{e}\n\{usage}")
  }

  if files is [old_path, new_path] {
    let old_source = @fs.read_file_to_string(old_path) catch {
      e => fatal("failed to read \{old_path}: \{e}")
    }
    let new_source = @fs.read_file_to_string(new_path) catch {
      e => fatal("failed to read \{new_path}: \{e}")
    }
    let graph_limit = parse_graph_limit(graph_limit_text.val) catch {
      e => fatal("invalid --graph-limit value \{graph_limit_text.val}: \{e}")
    }
    let result = @tool.diff_text(
      old_path,
      old_source,
      new_path,
      new_source,
      options=@tool.DiffOptions::new(
        graph_limit~,
        context_lines=3,
        use_color=use_color.val,
      ),
    )
    println(result.rendered)
  } else {
    fatal(usage)
  }
}
