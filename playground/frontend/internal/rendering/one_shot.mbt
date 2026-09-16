///|
// A completed effect can remain in a scheduler queue's backing buffer. Retain
// only an empty cell after invocation, never a model snapshot or a child root.
// Keep this factory separate from the region construction scope as well.
fn once(action : () -> Unit) -> (&@cmd.Scheduler) -> Unit {
  let pending = Ref(Some(action))
  _ => {
    if pending.val is Some(action) {
      pending.val = None
      action()
    }
  }
}
