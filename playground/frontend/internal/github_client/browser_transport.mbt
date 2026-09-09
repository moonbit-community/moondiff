///|
let client : Client = Client::new({ send: browser_send, delay: browser_delay, })

///|
fn browser_send(
  path : String,
  meth : String,
  csrf : String,
  body : String,
  completed : (Result[(Int, String), String]) -> Unit,
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
extern "js" fn fetch_text(
  path : String,
  meth : String,
  csrf : String,
  body : String,
  completed : (Int, String) -> Unit,
  failed : (String) -> Unit,
) -> () -> Unit =
  #| (path, method, csrf, body, completed, failed) => {
  #|   const controller = new AbortController();
  #|   Promise.resolve().then(() => fetch(path, { method, credentials: 'same-origin', cache: 'no-store', signal: controller.signal,
  #|     headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
  #|     ...(method === 'GET' ? {} : {body})
  #|   })).then(async response => completed(response.status, await response.text()))
  #|     .catch(error => failed(error.message || String(error)));
  #|   return () => controller.abort();
  #| }

///|
extern "js" fn browser_delay(ms : Int, callback : () -> Unit) -> () -> Unit =
  #| (ms, callback) => { const timer = setTimeout(callback, ms); return () => clearTimeout(timer); }

///|
pub fn dispose() -> Unit {
  client.dispose()
}

///|
pub fn cancel_before(generation : Int) -> @rabbita.Cmd {
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
  delay : Int,
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
