///|
fn lexing_then_recover(source : String) -> String {
  let texts = MbtToken::from_str(source)
  mbttokens_to_string(texts)
}

///|
test "001" {
  inspect(lexing_then_recover(mbt_001), content=mbt_001)
}

///|
test "attribute_name" {
  inspect(lexing_then_recover(mbt_attribute_name), content=mbt_attribute_name)
}

///|
test "double_to_string" {
  inspect(
    lexing_then_recover(mbt_double_to_string),
    content=mbt_double_to_string,
  )
}

///|
test "multiline_string_interp" {
  inspect(
    lexing_then_recover(mbt_multiline_string_interp),
    content=mbt_multiline_string_interp,
  )
}

///|
test "pattern_guard" {
  inspect(lexing_then_recover(mbt_pattern_guard), content=mbt_pattern_guard)
}

///|
test "range_pattern" {
  inspect(lexing_then_recover(mbt_range_pattern), content=mbt_range_pattern)
}

///|
test "string_escape" {
  inspect(lexing_then_recover(mbt_string_escape), content=mbt_string_escape)
}

///|
test "string_literal" {
  inspect(lexing_then_recover(mbt_string_literal), content=mbt_string_literal)
}

///|
test "super_trait3" {
  inspect(lexing_then_recover(mbt_super_trait3), content=mbt_super_trait3)
}

///|
test "trait_labelled" {
  inspect(lexing_then_recover(mbt_trait_labelled), content=mbt_trait_labelled)
}

///|
test "try" {
  inspect(lexing_then_recover(mbt_try), content=mbt_try)
}

///|
test "unicode_test" {
  inspect(lexing_then_recover(mbt_unicode_test), content=mbt_unicode_test)
}

///|
test "utf16_escape" {
  inspect(lexing_then_recover(mbt_utf16_escape), content=mbt_utf16_escape)
}
