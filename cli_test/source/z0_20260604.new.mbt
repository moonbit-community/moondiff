fn expect_command_ok(context : CommandContext, command : Command) -> Unit raise {
  match context.execute(command) {
    Some(diagnostic) =>
      fail("unexpected command diagnostic: \{diagnostic.format()}")
    None => ()
  }
}