fn run_command(context : CommandContext, command : Command) -> Unit raise {
  match context.execute(command) {
    Some(diagnostic) => inspect(diagnostic, content="ok")
    None => ()
  }
}