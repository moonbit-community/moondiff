///|
#external
pub type AbortController

///|
pub extern "js" fn AbortController::new() -> AbortController = "() => new AbortController()"

///|
pub extern "js" fn AbortController::abort(self : AbortController) -> Unit = "self => self.abort()"

///|
pub extern "js" fn AbortController::signal(self : AbortController) -> @js.Value = "self => self.signal"

///|
pub extern "js" fn AbortController::aborted(self : AbortController) -> Bool = "self => self.signal.aborted"

///|
#external
pub type Response

///|
pub extern "js" fn fetch(
  url : String,
  options : @js.Value,
) -> @js.Promise[Response] = "(url, options) => fetch(url, options)"

///|
pub extern "js" fn Response::status(self : Response) -> Int32 = "self => self.status"

///|
pub extern "js" fn Response::ok(self : Response) -> Bool = "self => self.ok"

///|
pub extern "js" fn Response::header(
  self : Response,
  name : String,
) -> @js.Nullable[String] = "(self, name) => self.headers.get(name)"

///|
pub extern "js" fn Response::has_header(self : Response, name : String) -> Bool = "(self, name) => self.headers.has(name)"

///|
pub extern "js" fn Response::text(self : Response) -> @js.Promise[String] = "self => self.text()"

///|
#external
pub type Reader

///|
pub extern "js" fn Response::reader(self : Response) -> Reader = "self => self.body.getReader()"

///|
pub extern "js" fn Reader::read(self : Reader) -> @js.Promise[@js.Value] = "self => self.read()"

///|
pub extern "js" fn Reader::cancel(self : Reader) -> @js.Promise[Unit] = "self => self.cancel()"

///|
pub extern "js" fn chunk_bytes(chunk : @js.Value) -> Bytes = "chunk => chunk.value"
