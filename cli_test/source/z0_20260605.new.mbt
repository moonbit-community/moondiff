///|
fn expect_parse_ok(input : String, expected : String) -> Unit raise {
  match parse_program(input) {
    Ok(exprs) =>
      if exprs.length() == 0 {
        abort("expected parsed expression")
      } else {
        inspect(exprs[0], content=expected)
      }
    Err(diagnostic) =>
      abort("unexpected parse diagnostic: \{diagnostic.format()}")
  }
}

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
  expect_parse_ok("; comment\np", "Atom(\"p\")")
}

///|
test "sexpr_parses_nested_lists" {
  expect_parse_ok(
    "; comment\n(assert (and p (not q)))", "List([Atom(\"assert\"), List([Atom(\"and\"), Atom(\"p\"), List([Atom(\"not\"), Atom(\"q\")])])])",
  )
}

///|
test "sexpr_parses_quoted_strings" {
  expect_parse_ok(
    "(echo \"a \"\"quote\"\"\")", "List([Atom(\"echo\"), StringLit(\"a \\\"quote\\\"\")])",
  )
}

///|
test "sexpr_reports_unclosed_list" {
  expect_parse_err("(assert p", "line 1, col 1: unclosed list")
}

///|
test "sexpr_reports_unclosed_string" {
  expect_parse_err("\"unterminated", "line 1, col 1: unclosed string")
}

///|
test "sexpr_reports_extra_right_paren" {
  expect_parse_err(")", "line 1, col 1: extra ')'")
}