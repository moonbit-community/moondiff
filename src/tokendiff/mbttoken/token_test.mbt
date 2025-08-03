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

// test "range_pattern.mbt_" {
//   lexing_then_recover("range_pattern.mbt_")
// }
