///|
priv enum ScanMode {
  Undecided
  Generic
  Shell
  Json
}

///|
priv enum QuoteState {
  Unquoted
  SingleQuoted
  DoubleQuoted
}

///|
priv struct ShellState {
  mut quote : QuoteState
  mut command : Bool
  mut substitution_depth : Int
}

///|
fn ShellState::new() -> ShellState {
  { quote: Unquoted, command: true, substitution_depth: 0, }
}

///|
priv struct InstructionState {
  root : String
  mut effective : String
  mut mode : ScanMode
  mut prefix : Bool
  mut quote : QuoteState
  shell : ShellState
  mut json_string : Bool
  mut argument_index : Int
}

///|
fn InstructionState::new(root : String) -> InstructionState {
  {
    root,
    effective: root,
    mode: Undecided,
    prefix: true,
    quote: Unquoted,
    shell: ShellState::new(),
    json_string: false,
    argument_index: 0,
  }
}

///|
priv struct PendingHeredoc {
  delimiter : String
  strip_tabs : Bool
  expand : Bool
  shell : Bool
  shell_state : ShellState
}
