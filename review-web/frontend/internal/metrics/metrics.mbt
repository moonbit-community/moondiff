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
pub fn counter(kind : String, delta : Int32) -> Unit {
  if sink() is Some(sink) {
    increment(object(sink, "counters"), kind, delta)
  }
}

///|
// Publish only scalars, never nodes, callbacks or the actual application state.
pub fn[T] state(kind : String, key : String, value : T) -> Unit {
  if sink() is Some(sink) {
    object(sink, kind).set_with_string(key, value)
  }
}

///|
let starts : Map[String, Double] = Map([])

///|
let samples : Map[String, Array[Double]] = Map([])

///|
pub fn pending(name : String) -> Bool {
  sink() is Some(_) && starts.contains(name)
}

///|
pub fn begin(name : String) -> Unit {
  if sink() is Some(_) {
    if name == "click_to_diff" {
      starts.remove("click_to_diff_cold")
      starts.remove("click_to_diff_prefetch")
    }
    starts[name] = @browser.date_now()
  }
}

///|
pub fn finish(name : String) -> Unit {
  guard sink() is Some(sink) && starts.get(name) is Some(start) else { return }
  starts.remove(name)
  let values = samples.get(name).unwrap_or([])
  values.push(@browser.date_now() - start)
  if values.length() > 128 {
    ignore(values.remove(0))
  }
  samples[name] = values
  let ordered = values.copy()
  ordered.sort()
  let target = object(object(sink, "timings"), name)
  target.set_with_string("samples", values.copy())
  target.set_with_string("p50", ordered[(ordered.length() - 1) / 2])
  target.set_with_string("p95", ordered[(ordered.length() * 95 + 99) / 100 - 1])
  if name == "click_to_diff" {
    finish("click_to_diff_cold")
    finish("click_to_diff_prefetch")
  }
}

///|
pub fn cache_outcome(hit : Bool) -> Unit {
  guard sink() is Some(sink) else { return }
  if starts.get("click_to_diff") is Some(start) {
    starts[if hit { "click_to_diff_prefetch" } else { "click_to_diff_cold" }] = start
  }
  let target = object(sink, "prefetch")
  increment(target, "visits", 1)
  if hit {
    increment(target, "hits", 1)
  }
  let visits : Int32 = target.get_with_string("visits")
  let raw : @js.Value = target.get_with_string("hits")
  let hits : Int32 = if raw.is_undefined() { 0 } else { raw.cast() }
  target.set_with_string("hit_rate", hits.to_double() / visits.to_double())
}
