///|
// The browser harness owns the optional sink; all bookkeeping is MoonBit.
fn sink() -> @js.Value? {
  let value : @js.Value = @js.globalThis.get_with_string("__moondiffMetrics")
  if value.is_undefined() || value.is_null() {
    None
  } else {
    Some(value)
  }
}

///|
fn object(parent : @js.Value, key : String) -> @js.Value {
  let value : @js.Value = parent.get_with_string(key)
  if value.is_undefined() || value.is_null() {
    let value = @js.Object::new().to_value()
    parent.set_with_string(key, value)
    value
  } else {
    value
  }
}

///|
fn increment(parent : @js.Value, key : String, delta : Int32) -> Unit {
  let value : @js.Value = parent.get_with_string(key)
  let count : Int32 = if value.is_undefined() || value.is_null() {
    0
  } else {
    value.cast()
  }
  parent.set_with_string(key, count + delta)
}

///|
pub fn count(path : String, operation : String) -> Unit {
  if sink() is Some(sink) {
    increment(object(object(sink, "files"), path), operation, 1)
  }
}

///|
pub fn active(kind : String, delta : Int32) -> Unit {
  if sink() is Some(sink) {
    increment(object(sink, "active"), kind, delta)
  }
}

///|
// Publish only scalars, never nodes, callbacks or the actual application state.
pub fn[T] state(kind : String, key : String, value : T) -> Unit {
  if sink() is Some(sink) {
    object(sink, kind).set_with_string(key, value)
  }
}
