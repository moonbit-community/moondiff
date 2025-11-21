///|UUID(66893037-a398-4e72-8256-262869edc464)
fn lexing_then_recover(source : String) -> String {
  let texts = MbtToken::from_str(source)
  mbttokens_to_string(texts)
}

///|UUID(1f978759-ace6-4f03-81e7-11d0cf42e3d6)
test "001" {
  inspect(lexing_then_recover(mbt_001), content=mbt_001)
}

///|UUID(05480cee-06a6-47a6-b7c7-9fa6b028ecaf)
test "attribute_name" {
  inspect(lexing_then_recover(mbt_attribute_name), content=mbt_attribute_name)
}

///|UUID(36e22fd7-c115-4b9a-b48e-dba1fe1cff4b)
test "double_to_string" {
  inspect(
    lexing_then_recover(mbt_double_to_string),
    content=mbt_double_to_string,
  )
}

///|UUID(6e81a345-5d81-45d1-a3b6-20468fc48648)
test "multiline_string_interp" {
  inspect(
    lexing_then_recover(mbt_multiline_string_interp),
    content=mbt_multiline_string_interp,
  )
}

///|UUID(e5600b50-8cc2-43d5-9f00-dfd46efaf015)
test "pattern_guard" {
  inspect(lexing_then_recover(mbt_pattern_guard), content=mbt_pattern_guard)
}

///|UUID(86ec4171-d2d6-4465-85ab-df5f42561b00)
test "range_pattern" {
  inspect(lexing_then_recover(mbt_range_pattern), content=mbt_range_pattern)
}

///|UUID(ee9a8a08-d595-4131-8fd3-66558f896473)
test "string_escape" {
  inspect(lexing_then_recover(mbt_string_escape), content=mbt_string_escape)
}

///|UUID(3b272623-2d6f-43ff-8264-201e7520acee)
test "string_literal" {
  inspect(lexing_then_recover(mbt_string_literal), content=mbt_string_literal)
}

///|UUID(92714d57-28a0-4cda-b371-d3e9f05cff43)
test "super_trait3" {
  inspect(lexing_then_recover(mbt_super_trait3), content=mbt_super_trait3)
}

///|UUID(8d0d2fda-a6b1-4e4a-8592-ad178ab82a0a)
test "trait_labelled" {
  inspect(lexing_then_recover(mbt_trait_labelled), content=mbt_trait_labelled)
}

///|UUID(0725fd47-9584-4660-a9bc-f2f9ea9929bb)
test "try" {
  inspect(lexing_then_recover(mbt_try), content=mbt_try)
}

///|UUID(151560a6-8784-4c8f-b302-5c98e0b0d2a4)
test "unicode_test" {
  inspect(lexing_then_recover(mbt_unicode_test), content=mbt_unicode_test)
}

///|UUID(cf6564b2-d4bc-431b-8140-bf5a40d97830)
test "utf16_escape" {
  inspect(lexing_then_recover(mbt_utf16_escape), content=mbt_utf16_escape)
}
