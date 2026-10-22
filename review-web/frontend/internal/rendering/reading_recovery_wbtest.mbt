///|
// These tests exercise scheduling without a browser. Geometry is covered by the
// gated browser tests; the sentinel must never be read by an obsolete callback.
extern "js" fn unused_reading_node() -> @dom.Element = "() => null"

///|
fn protected_reading(
  coordinator : Coordinator,
  id~ : Int32 = 1,
) -> ReadingProtection {
  let mount = settled_mount(coordinator, File("reading.mbt"), id + 8)
  let reading : ReadingProtection = {
    token: {
      id,
      generation: coordinator.generation,
      entry: "entry",
      cancelled: false,
      finished: false,
      auth_serial: 1,
      auth_requests: { 1: 0 },
      snapshot: false,
      comments_queued: 0,
      comments_refresh: None,
      viewed: None,
      merge: None,
    },
    region: mount.region,
    mount_instance: mount.instance,
    card: unused_reading_node(),
    anchor: unused_reading_node(),
    top: 83.25,
    emit: _ => @rabbita.none,
    stop: () => (),
    frame: 0,
    quiet: 0,
    revision: -1,
    layout_revision: -1,
  }
  coordinator.reading = Some(reading)
  reading
}

///|
test "unavailable capture synchronously finishes without cancelling or recapturing" {
  let coordinator = Coordinator::new()
  let reading = protected_reading(coordinator)
  coordinator.reading = None
  coordinator.configure_reading(Some(reading.token), _ => @rabbita.none)
  assert_true(reading.token.finished)
  assert_false(reading.token.cancelled)
  assert_true(coordinator.reading is None)
  coordinator.configure_reading(Some(reading.token), _ => @rabbita.none)
  assert_false(reading.token.cancelled)
  assert_true(coordinator.anchoring.owners.is_empty())
}

///|
test "reading merges retain the first baseline without taking the navigation slot or lock" {
  let coordinator = Coordinator::new()
  let reading = protected_reading(coordinator)
  coordinator.configure_reading(Some(reading.token), _ => @rabbita.none)
  coordinator.configure_reading(Some(reading.token), _ => @rabbita.none)
  assert_eq(coordinator.reading.unwrap().top, 83.25)
  assert_true(coordinator.navigation is None)
  assert_false(coordinator.progressive.navigation_locked)
  assert_true(coordinator.anchoring.owners.contains(Reading))
}

///|
test "reading waits for latest central and region tickets in either order" {
  for first_target in [true, false] {
    let coordinator = Coordinator::new()
    let reading = protected_reading(coordinator)
    let target = coordinator.mounts[reading.region]
    let above = settled_mount(coordinator, Toolbar, 1)
    let first = coordinator.begin_update(0, [])
    coordinator.region_changed(target)
    let stale = target.ticket()
    coordinator.region_changed(above)
    let latest = coordinator.begin_update(0, [])
    coordinator.region_changed(target)
    ignore(target.finish(stale))
    assert_false(coordinator.reading_ready(reading.token.id))
    coordinator.committed = first
    let earlier = if first_target { target } else { above }
    let later = if first_target { above } else { target }
    ignore(earlier.finish(earlier.ticket()))
    coordinator.pending.remove(earlier.region)
    coordinator.committed = latest
    assert_false(coordinator.reading_ready(reading.token.id))
    ignore(later.finish(later.ticket()))
    coordinator.pending.remove(later.region)
    assert_true(coordinator.reading_ready(reading.token.id))
    assert_false(coordinator.reading_ready(reading.token.id - 1))
  }
}

///|
test "navigation and synchronous cancellation invalidate reading and release only its anchor ownership" {
  let coordinator = Coordinator::new()
  let reading = protected_reading(coordinator)
  coordinator.anchoring.acquire(History)
  coordinator.anchoring.acquire(Reading)
  ignore(coordinator.begin_update(0, [page_navigation(reading.region)]))
  assert_true(reading.token.cancelled)
  assert_true(coordinator.reading is None)
  assert_true(coordinator.navigation is Some(_))
  assert_false(coordinator.anchoring.owners.contains(Reading))
  assert_true(coordinator.anchoring.owners.contains(History))
  coordinator.anchoring.release(History)
  assert_true(coordinator.anchoring.owners.is_empty())
  assert_true(coordinator.anchoring.saved is None)
}

///|
test "only a valid history restoration supersedes reading" {
  let coordinator = Coordinator::new()
  let reading = protected_reading(coordinator)
  let history : @application.HistoryRestoration = {
    generation: coordinator.generation,
    entry: "entry",
    cancelled: true,
  }
  let action = { ..page_navigation(Navigation), scope: HistoryLayout(history), }
  ignore(coordinator.begin_update(0, [action]))
  assert_true(coordinator.owns_reading(reading.token.id))
  history.cancelled = false
  ignore(coordinator.begin_update(0, [action]))
  assert_true(reading.token.cancelled)
  assert_true(coordinator.reading is None)
  assert_true(coordinator.navigation is Some(_))
}

///|
test "completed recovery cannot recapture while its cleanup message is queued" {
  let coordinator = Coordinator::new()
  let reading = protected_reading(coordinator)
  coordinator.end_reading(false)
  assert_true(reading.token.finished)
  assert_false(reading.token.cancelled)
  coordinator.configure_reading(Some(reading.token), _ => @rabbita.none)
  assert_true(coordinator.reading is None)
  assert_false(reading.token.cancelled)
  assert_true(coordinator.anchoring.owners.is_empty())
}

///|
test "old frames and unmounts cannot cancel a newer reading mount" {
  let coordinator = Coordinator::new()
  let old = protected_reading(coordinator)
  let old_mount = coordinator.mounts[old.region]
  ignore(coordinator.begin_update(1, []))
  assert_true(old.token.cancelled)
  let next = protected_reading(coordinator, id=2)
  coordinator.reading_frame(old.token.id)
  ignore(coordinator.invalidate(old_mount))
  assert_true(coordinator.owns_reading(next.token.id))
  next.token.cancelled = true
  assert_false(coordinator.owns_reading(next.token.id))
  coordinator.configure_reading(Some(next.token), _ => @rabbita.none)
  assert_true(coordinator.reading is None)
  assert_true(coordinator.anchoring.owners.is_empty())
}
