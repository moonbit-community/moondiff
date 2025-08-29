///|
let dir : String = "./src/tokendiff/mbttoken/fixtures/"

///|
fn lexing_then_recover(filename : String) -> Unit raise {
  let str = @fs.read_file_to_string(dir + filename)
  let triples = @lexer.tokens_from_string(comment=true, str).tokens
  let line_widths = @span.LineWidths::from_str(str)
  let texts = MbtToken::from_triples(triples, line_widths)
  let str = mbttokens_to_string(texts)
  @fs.write_string_to_file(dir + filename, str)
}

///|
test "001.mbt_" {
  lexing_then_recover("001.mbt_")
}

///|
test "attribute_name.mbt_" {
  lexing_then_recover("attribute_name.mbt_")
}

///|
test "double_to_string.mbt_" {
  lexing_then_recover("double_to_string.mbt_")
}

///|
test "multiline_string_interp.mbt_" {
  lexing_then_recover("multiline_string_interp.mbt_")
}

///|
test "pattern_guard.mbt_" {
  lexing_then_recover("pattern_guard.mbt_")
}

///|
test "range_pattern.mbt_" {
  lexing_then_recover("range_pattern.mbt_")
}

///|
test "string_escape.mbt_" {
  lexing_then_recover("string_escape.mbt_")
}

///|
test "string_literal.mbt_" {
  lexing_then_recover("string_literal.mbt_")
}

///|
test "super_trait3.mbt_" {
  lexing_then_recover("super_trait3.mbt_")
}

///|
test "trait_labelled.mbt_" {
  lexing_then_recover("trait_labelled.mbt_")
}

///|
test "try.mbt_" {
  lexing_then_recover("try.mbt_")
}

///|
test "unicode_test.mbt_" {
  lexing_then_recover("unicode_test.mbt_")
}

///|
test "utf16_escape.mbt_" {
  lexing_then_recover("utf16_escape.mbt_")
}
