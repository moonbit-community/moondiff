///|
let client : Client = Client::new({
  send: browser_send,
  delay: browser_delay,
  visible: () => !@browser.has_window() || !@dom.document().hidden(),
})

///|
fn browser_send(
  path : String,
  meth : String,
  csrf : String,
  body : String,
  completed : (Result[(Int32, String), String]) -> Unit,
) -> () -> Unit {
  fetch_text(
    path,
    meth,
    csrf,
    body,
    (status, text) => completed(Ok((status, text))),
    detail => completed(Err(detail)),
  )
}

///|
fn fetch_text(
  path : String,
  meth : String,
  csrf : String,
  body : String,
  completed : (Int32, String) -> Unit,
  failed : (String) -> Unit,
) -> () -> Unit {
  let controller = @browser.AbortController::new()
  let options = @js.Object::new()
  options.set("method", meth)
  options.set("credentials", "same-origin")
  options.set("cache", "no-store")
  options.set("signal", controller.signal())
  let headers = @js.Object::new()
  headers.set("Content-Type", "application/json")
  headers.set("X-CSRF-Token", csrf)
  options.set("headers", headers.to_value())
  if meth != "GET" {
    options.set("body", body)
  }
  // Retain the original Promise.resolve().then(fetch) microtask boundary.
  @dom.window().queue_microtask(() => {
    @browser.subscribe(
      @browser.fetch(path, options.to_value()),
      response => {
        @browser.subscribe(
          response.text(),
          text => completed(response.status(), text),
          error => failed(@browser.error_message(error)),
        )
      },
      error => failed(@browser.error_message(error)),
    )
  })
  () => controller.abort()
}

///|
fn browser_delay(ms : Int32, callback : () -> Unit) -> () -> Unit {
  let timer = @dom.window().set_timeout(callback, ms)
  () => @dom.window().clear_timeout(timer)
}

///|
pub fn dispose() -> Unit {
  client.dispose()
}

///|
pub fn cancel_before(generation : Int32) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => client.cancel_before(generation))
}

///|
fn[T] command(
  start : ((Result[T, Error]) -> Unit) -> Unit,
  emit : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    start(result => {
      if result is Err(Cancelled) {
        return
      }
      scheduler.add(emit(result))
    })
  })
}

///|
pub fn auth_status_request(
  emit : @rabbita.Emit[Result[@protocol.ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  command(done => client.status(done), emit)
}

///|
pub fn auth_device_request(
  action : DeviceAction,
  id : String,
  delay : Int32,
  emit : @rabbita.Emit[Result[@protocol.DeviceResponse, Error]],
) -> @rabbita.Cmd {
  command(done => client.device(action, id, delay, done), emit)
}

///|
pub fn auth_logout_request(
  emit : @rabbita.Emit[Result[@protocol.ApiAuthStatus, Error]],
) -> @rabbita.Cmd {
  command(done => client.logout(done), emit)
}
