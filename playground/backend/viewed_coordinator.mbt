///|
priv struct ViewedCoordinator {
  mutex : @async.Mutex
  mut users : Int
}

///|
// Register before any suspension (including token refresh). Mutex acquisition
// is FIFO and cancellation safe. Count holders and waiters so cancelling a
// queued request cannot remove a coordinator still owned by a running write.
async fn[T] App::with_viewed_scope(
  self : App,
  session : Session?,
  p : @protocol.PullViewedGet,
  action : async () -> T,
) -> T {
  guard session is Some(session) && !session.tokens.is_empty() else {
    raise RpcError(
      401, "authentication_required", "Sign in to sync Viewed files with GitHub.",
    )
  }
  let key = "\{session.user}:\{p.owner.to_lower()}/\{p.repo.to_lower()}:\{p.number}"
  let coordinator = match self.viewed_scopes.get(key) {
    Some(coordinator) => coordinator
    None => {
      let coordinator = { mutex: @async.Mutex(), users: 0, }
      self.viewed_scopes[key] = coordinator
      coordinator
    }
  }
  coordinator.users += 1
  defer {
    coordinator.users -= 1
    if coordinator.users == 0 {
      self.viewed_scopes.remove(key)
    }
  }
  // Propagate cancellation/timeouts; never run the action after a failed wait.
  coordinator.mutex.acquire()
  defer coordinator.mutex.release()
  action()
}
