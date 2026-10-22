///|
pub fn[T] subscribe(
  promise : @js.Promise[T],
  ok : (T) -> Unit,
  failed : (@js.Value) -> Unit,
) -> Unit {
  subscribe_raw(
    @js.Value::cast_from(promise),
    value => ok(value.cast()),
    failed,
  )
}

///|
extern "js" fn subscribe_raw(
  promise : @js.Value,
  ok : (@js.Value) -> Unit,
  failed : (@js.Value) -> Unit,
) -> Unit =
  #| (promise, ok, failed) => { promise.then(ok).catch(failed); }

///|
pub extern "js" fn error_message(error : @js.Value) -> String = "error => error.message || String(error)"

///|
pub fn copy_text(text : String, completed : (Bool) -> Unit) -> Unit {
  subscribe(
    @dom.window().navigator().clipboard().write_text(text),
    _ => completed(true),
    _ => completed(false),
  )
}
