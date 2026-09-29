///|
fn is_instruction(word : StringView) -> Bool {
  match word.to_upper() {
    "ADD"
    | "ARG"
    | "CMD"
    | "COPY"
    | "ENTRYPOINT"
    | "ENV"
    | "EXPOSE"
    | "FROM"
    | "HEALTHCHECK"
    | "LABEL"
    | "MAINTAINER"
    | "ONBUILD"
    | "RUN"
    | "SHELL"
    | "STOPSIGNAL"
    | "USER"
    | "VOLUME"
    | "WORKDIR" => true
    _ => false
  }
}

///|
fn is_shell_instruction(word : String) -> Bool {
  word is ("RUN" | "CMD" | "ENTRYPOINT")
}

///|
fn supports_json(word : String) -> Bool {
  word is ("RUN" | "CMD" | "ENTRYPOINT" | "SHELL" | "ADD" | "COPY")
}

///|
fn is_shell_control(word : StringView) -> Bool {
  match word {
    "if"
    | "then"
    | "else"
    | "elif"
    | "fi"
    | "for"
    | "while"
    | "until"
    | "do"
    | "done"
    | "case"
    | "esac"
    | "in"
    | "function"
    | "select"
    | "time"
    | "coproc" => true
    _ => false
  }
}

///|
fn is_boolean(word : StringView) -> Bool {
  word is ("true" | "false" | "TRUE" | "FALSE")
}

///|
fn is_decimal(word : StringView) -> Bool {
  if word.is_empty() {
    return false
  }
  for char in word {
    if !(char is ('0'..='9')) {
      return false
    }
  }
  true
}
