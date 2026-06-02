///|UUID(781bc9a3-8ba9-4dfc-90fc-a08894f78b78)
let default_graph_limit_text = "3000000"

///|UUID(64cf617a-ebad-4e41-ada4-c89891bd0d7c)
priv struct CliOptions {
  old_path : String
  new_path : String
  graph_limit_text : String
  use_color : Bool
}

///|UUID(9d8d9872-ee94-460e-99e1-8590c4ea178f)
fn parse_graph_limit(text : String) -> UInt raise {
  @string.parse_int(text).reinterpret_as_uint()
}

///|UUID(ab140a6a-3c91-4f23-a339-d48e58607db8)
fn[T] fatal(message : String) -> T {
  @miniio.stderr.write_text("\{message}\n") catch {
    _ => ()
  }
  @miniio.exit(1)
  panic()
}

///|UUID(5fb97ce8-62bb-4966-b0a3-61d2905cbf95)
fn write_stdout(message : String) -> Unit {
  @miniio.stdout.write_text(message) catch {
    e => fatal("failed to write stdout: \{e}")
  }
}

///|UUID(07090eb9-2c1a-4f1c-902b-014898f20578)
fn moondiff_command() -> @argparse.Command {
  @argparse.Command(
    "astdiff",
    options=[
      @argparse.OptionArg(
        "graph-limit",
        short='g',
        about="Maximum AST graph size before falling back to line diff",
        default_values=[default_graph_limit_text],
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "no-color",
        about="Disable ANSI colors",
        action=@argparse.FlagAction::SetFalse,
      ),
    ],
    positionals=[
      @argparse.PositionArg("old-file", num_args=@argparse.ValueRange::single()),
      @argparse.PositionArg("new-file", num_args=@argparse.ValueRange::single()),
    ],
  )
}

///|UUID(b1b5b427-9f37-43ac-afd8-b018ac69375b)
fn single_value(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) => value
    _ => panic()
  }
}

///|UUID(83ae8311-feba-4621-af44-82221c52a060)
fn parse_cli_args(argv : ArrayView[String]) -> CliOptions raise {
  let matches = moondiff_command().parse(argv~)
  {
    old_path: single_value(matches, "old-file"),
    new_path: single_value(matches, "new-file"),
    graph_limit_text: single_value(matches, "graph-limit"),
    use_color: matches.flags.get("no-color").unwrap_or(true),
  }
}

///|UUID(df9a5580-e3b6-4bda-b76f-f1c9dc4a95c0)
fn program_args() -> ArrayView[String] {
  let args = @miniio.args_get() catch {
    e => fatal("failed to read command line arguments: \{e}")
  }
  if args.length() > 1 {
    args[1:]
  } else {
    []
  }
}

///|UUID(5da5cf7f-b7c4-474b-a87a-be6436f0b5f2)
fn main {
  let options = parse_cli_args(program_args()) catch { e => fatal(e.to_string()) }
  let old_source = @miniio.read_text_file(options.old_path) catch {
    e => fatal("failed to read \{options.old_path}: \{e}")
  }
  let new_source = @miniio.read_text_file(options.new_path) catch {
    e => fatal("failed to read \{options.new_path}: \{e}")
  }
  let graph_limit = parse_graph_limit(options.graph_limit_text) catch {
    e => fatal("invalid --graph-limit value \{options.graph_limit_text}: \{e}")
  }
  let result = @tool.diff_text(
    options.old_path,
    old_source,
    options.new_path,
    new_source,
    options=@tool.DiffOptions::new(
      graph_limit~,
      context_lines=3,
      use_color=options.use_color,
    ),
  )
  write_stdout("\{result.rendered}\n")
}
