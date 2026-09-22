///|
/// Per-pull synchronization state for Viewed mutations.
pub(all) struct ViewedCoordinator {
  mutex : @async.Mutex
  mut users : Int
}
