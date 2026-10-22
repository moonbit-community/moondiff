///|
// JS exceptions are translated at the host boundary, before MoonBit handles them.
extern "js" fn storage_get_raw(key : String) -> @js.Value = "key => sessionStorage.getItem(key)"

///|
extern "js" fn storage_key_raw(index : Int32) -> @js.Value = "index => sessionStorage.key(index)"

///|
extern "js" fn storage_length_raw() -> @js.Value = "() => sessionStorage.length"

///|
extern "js" fn storage_set_raw(key : String, value : String) -> @js.Value = "(key, value) => sessionStorage.setItem(key, value)"

///|
extern "js" fn storage_remove_raw(key : String) -> @js.Value = "key => sessionStorage.removeItem(key)"

///|
fn string_option(value : @js.Value) -> String? {
  if value.is_null() {
    None
  } else {
    Some(value.cast())
  }
}

///|
pub fn storage_get(key : String) -> String? raise {
  @js.Error_::wrap(() => storage_get_raw(key), map_ok=string_option)
}

///|
pub fn storage_key(index : Int32) -> String? raise {
  @js.Error_::wrap(() => storage_key_raw(index), map_ok=string_option)
}

///|
pub fn storage_length() -> Int32 raise {
  @js.Error_::wrap(storage_length_raw, map_ok=value => value.cast())
}

///|
pub fn storage_set(key : String, value : String) -> Unit raise {
  @js.Error_::wrap(() => storage_set_raw(key, value), map_ok=_ => ())
}

///|
pub fn storage_remove(key : String) -> Unit raise {
  @js.Error_::wrap(() => storage_remove_raw(key), map_ok=_ => ())
}
