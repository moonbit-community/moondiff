///|
#warnings("-result_error_return")
fn[T] Client::request_result(
  self : Client,
  result : Result[T, Error],
  authenticated : Bool,
) -> Result[T, Error] {
  guard result is Err(error) && rate_limited(error) else { return result }
  let reason = if authenticated {
    AuthenticatedRequests
  } else {
    AnonymousRequests
  }
  if authenticated == self.authenticated {
    self.pause_sources(reason)
  }
  Err(RateLimited(reason))
}

///|
fn Client::pause_sources(self : Client, reason : RateLimitReason) -> Unit {
  self.workspace.source_pause = Some(reason)
  // Retire queued subscriptions with an explicit paused result. In-flight
  // requests retain their slots and may still populate immutable source caches.
  let queued = self.workspace.reads.iter().collect()
  for (key, pending) in queued {
    if pending.active && !pending.started && pending.request is ContentGet(_) {
      pending.active = false
      self.workspace.reads.remove(key)
      let waiters = pending.waiters
      pending.waiters = []
      for waiter in waiters {
        (waiter.done)(Err(RateLimited(reason)))
      }
    }
  }
}

///|
// The application calls this only after identity and (for PRs) version checks.
pub fn resume_anonymous_sources(generation : Int32) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    if generation >= client.generation &&
      client.authenticated &&
      client.workspace.source_pause == Some(AnonymousRequests) {
      client.workspace.source_pause = None
      client.pump_sources()
    }
  })
}
