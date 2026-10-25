///|
/// Per-pull synchronization state for Viewed mutations.
pub(all) struct ViewedCoordinator {
  mutex : @async.Mutex
  mut users : Int32
}

///|
/// A snapshot task is registered before its first metadata read. Lazy cancels
/// the worker when its last waiter leaves; generation guards delayed cleanup.
pub(all) struct SnapshotRead {
  pending : @async.Lazy[@protocol.ApiPullSnapshotResult]
  generation : Int64
  mut waiters : Int32
}
