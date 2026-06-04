///|
fn expect_parse_err(input : String, expected : String) -> Unit raise {
  match parse_program(input) {
    Ok(exprs) =>
      abort("expected parse diagnostic, got \{exprs.length()} expression(s)")
    Err(diagnostic) => inspect(diagnostic, content=expected)
  }
}



///|
test "sexpr_skips_comments" {
  inspect_parse("; comment\np", "Atom(\"p\")")
}

///|
test "sexpr_parses_nested_lists" {
  inspect_parse(
    "; comment\n(assert (and p (not q)))", "List([Atom(\"assert\"), List([Atom(\"and\"), Atom(\"p\"), List([Atom(\"not\"), Atom(\"q\")])])])",
  )
}

///|
test "sexpr_parses_quoted_strings" {
  inspect_parse(
    "(echo \"a \"\"quote\"\"\")", "List([Atom(\"echo\"), StringLit(\"a \\\"quote\\\"\")])",
  )
}

///|
test "sexpr_reports_unclosed_list" {
  inspect_parse("(assert p", "line 1, col 1: unclosed list")
}

///|
test "sexpr_reports_unclosed_string" {
  inspect_parse("\"unterminated", "line 1, col 1: unclosed string")
}

///|
test "sexpr_reports_extra_right_paren" {
  inspect_parse(")", "line 1, col 1: extra ')'")
}