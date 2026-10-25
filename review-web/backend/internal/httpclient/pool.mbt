///|
priv struct Connection {
  id : Int64
  client : @http.Client
  mut idle_since : Int64
}

///|
/// A bounded HTTP/1.1 pool for one configured origin. Only User-Agent is
/// persistent; credentials and body headers belong to individual requests.
pub struct Pool {
  priv origin : String
  priv permits : @async.Semaphore
  priv idle_ms : Int64
  priv mut idle : Array[Connection]
  priv mut connections : Array[Connection]
  priv mut generation : Int64
  priv mut closed : Bool
}

///|
pub fn Pool::Pool(origin : String, capacity : Int32) -> Pool {
  {
    origin,
    permits: Semaphore(capacity),
    idle_ms: 15000,
    idle: [],
    connections: [],
    generation: 0,
    closed: false,
  }
}

///|
fn Pool::discard(self : Pool, connection : Connection) -> Unit {
  connection.client.close()
  self.connections = self.connections.filter(c => c.id != connection.id)
}

///|
fn Pool::expire_idle(self : Pool) -> Unit {
  let now = @async.now()
  self.idle = self.idle.filter(connection => {
    if now - connection.idle_since > self.idle_ms {
      self.discard(connection)
      false
    } else {
      true
    }
  })
}

///|
/// Close idle and borrowed connections. Connecting clients clean up through
/// their constructor when the server's enclosing task group is cancelled.
pub fn Pool::close(self : Pool) -> Unit {
  self.closed = true
  for connection in self.connections {
    connection.client.close()
  }
  self.connections = []
  self.idle = []
}

///|
async fn Pool::borrow(self : Pool, fresh~ : Bool) -> (Connection, Bool) {
  // The caller reserves a permit before connecting and normally reuses idle
  // clients first. Recovery replaces its discarded client with a fresh one.
  // Thus connecting + borrowed + idle never exceeds the pool's capacity.
  self.expire_idle()
  guard !self.closed else { raise @io.ReaderClosed }
  if !fresh && self.idle.pop() is Some(connection) {
    return (connection, true)
  }
  let client = @http.Client(self.origin, headers={ "User-Agent": "moondiff" })
  if self.closed {
    client.close()
    raise @io.ReaderClosed
  }
  self.generation += 1
  let connection = { id: self.generation, client, idle_since: 0, }
  self.connections.push(connection)
  (connection, false)
}

///|
fn Pool::give_back(
  self : Pool,
  connection : Connection,
  reusable : Bool,
) -> Unit {
  self.expire_idle()
  if reusable && !self.closed && !@async.is_being_cancelled() {
    connection.idle_since = @async.now()
    self.idle.push(connection)
  } else {
    self.discard(connection)
  }
}
