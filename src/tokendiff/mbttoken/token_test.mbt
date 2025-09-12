///|
let dir : String = "./src/tokendiff/mbttoken/fixtures/"

///|
fn lexing_then_recover(t : @test.T, filename : String) -> Unit raise {
  let str = @fs.read_file_to_string(dir + filename + ".mbt_")
  let triples = @lexer.tokens_from_string(comment=true, str).tokens
  let line_widths = @span.LineWidths::from_str(str)
  let texts = MbtToken::from_triples(triples, line_widths)
  let str = mbttokens_to_string(texts)
  t.write(str)
  t.snapshot(filename~)
}

///|
test "001.mbt_" (t : @test.T) {
  lexing_then_recover(t, "001")
}

///|
test "attribute_name.mbt_" (t : @test.T) {
  lexing_then_recover(t, "attribute_name")
}

///|
test "double_to_string.mbt_" (t : @test.T) {
  lexing_then_recover(t, "double_to_string")
}

///|
test "multiline_string_interp.mbt_" (t : @test.T) {
  lexing_then_recover(t, "multiline_string_interp")
}

///|
test "pattern_guard.mbt_" (t : @test.T) {
  lexing_then_recover(t, "pattern_guard")
}

///|
test "range_pattern.mbt_" (t : @test.T) {
  lexing_then_recover(t, "range_pattern")
}

///|
test "string_escape.mbt_" (t : @test.T) {
  lexing_then_recover(t, "string_escape")
}

///|
test "string_literal.mbt_" (t : @test.T) {
  lexing_then_recover(t, "string_literal")
}

///|
test "super_trait3.mbt_" (t : @test.T) {
  lexing_then_recover(t, "super_trait3")
}

///|
test "trait_labelled.mbt_" (t : @test.T) {
  lexing_then_recover(t, "trait_labelled")
}

///|
test "try.mbt_" (t : @test.T) {
  lexing_then_recover(t, "try")
}

///|
test "unicode_test.mbt_" (t : @test.T) {
  lexing_then_recover(t, "unicode_test")
}

///|
test "utf16_escape.mbt_" (t : @test.T) {
  lexing_then_recover(t, "utf16_escape")
}
