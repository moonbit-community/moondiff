///|
fn settled_mount(
  coordinator : Coordinator,
  region : @application.Region,
  instance : Int,
) -> Mount {
  let mount = {
    ..test_mount(),
    generation: coordinator.generation,
    region,
    instance,
    revision: 0,
    committed: 0,
  }
  coordinator.mounts[region] = mount
  mount
}

///|
fn page_navigation(target : @application.Region) -> @application.AfterCommit {
  { target, scope: PageLayout, command: @rabbita.none, navigation: Cancel, }
}

///|
test "page navigation waits for central projection and every scheduled region in either order" {
  for target_first in [true, false] {
    let coordinator = Coordinator::new()
    let above = settled_mount(coordinator, File("above.mbt"), 1)
    let target = settled_mount(coordinator, File("target.mbt"), 2)
    let revision = coordinator.begin_update(0, [page_navigation(target.region)])
    let sequence = coordinator.navigation_sequence
    // No regional ticket exists yet: the pending central projection still blocks.
    assert_true(coordinator.take_navigation(sequence) is None)
    coordinator.region_changed(above)
    coordinator.region_changed(target)
    let first = if target_first { target } else { above }
    let last = if target_first { above } else { target }
    coordinator.finish_region(first, first.ticket())
    assert_true(coordinator.take_navigation(sequence) is None)
    coordinator.finish_update(0, revision)
    assert_true(coordinator.take_navigation(sequence) is None)
    coordinator.finish_region(last, last.ticket())
    assert_true(coordinator.take_navigation(sequence) is Some(_))
    assert_true(coordinator.take_navigation(sequence) is None)
  }
}

///|
test "waiting navigation includes later central updates, regional revisions and additional regions" {
  let coordinator = Coordinator::new()
  let above = settled_mount(coordinator, File("above.mbt"), 1)
  let target = settled_mount(coordinator, File("target.mbt"), 2)
  let toolbar = settled_mount(coordinator, Toolbar, 3)
  let first = coordinator.begin_update(0, [page_navigation(target.region)])
  let sequence = coordinator.navigation_sequence
  coordinator.region_changed(above)
  let old_ticket = above.ticket()
  coordinator.finish_update(0, first)
  let latest = coordinator.begin_update(0, [])
  coordinator.region_changed(above)
  coordinator.region_changed(toolbar)
  coordinator.finish_region(above, old_ticket)
  assert_eq(coordinator.pending.length(), 2)
  coordinator.finish_update(0, first)
  assert_eq(coordinator.committed, first)
  coordinator.finish_region(above, above.ticket())
  coordinator.finish_region(toolbar, toolbar.ticket())
  assert_true(coordinator.take_navigation(sequence) is None)
  coordinator.finish_update(0, latest)
  assert_true(coordinator.take_navigation(sequence) is Some(_))
}

///|
test "new navigation replaces the old intent immediately even when its target needs no update" {
  let coordinator = Coordinator::new()
  let a = settled_mount(coordinator, File("a.mbt"), 1)
  let b = settled_mount(coordinator, File("b.mbt"), 2)
  let first = coordinator.begin_update(0, [page_navigation(a.region)])
  let old_sequence = coordinator.navigation_sequence
  coordinator.region_changed(a)
  coordinator.finish_update(0, first)
  let latest = coordinator.begin_update(0, [page_navigation(b.region)])
  let sequence = coordinator.navigation_sequence
  assert_eq(sequence, old_sequence + 1)
  // The old region finishes before the new central commit.
  coordinator.finish_region(a, a.ticket())
  assert_true(coordinator.take_navigation(old_sequence) is None)
  assert_true(coordinator.take_navigation(sequence) is None)
  coordinator.finish_update(0, latest)
  assert_true(coordinator.navigation.unwrap().action.target == b.region)
  // A previously queued command cannot consume the newer request either.
  assert_true(coordinator.take_navigation(old_sequence) is None)
  assert_true(coordinator.take_navigation(sequence) is Some(_))
}

///|
test "stale generation and mount callbacks cannot release current navigation" {
  let coordinator = Coordinator::new()
  let old = settled_mount(coordinator, File("target.mbt"), 1)
  let revision = coordinator.begin_update(0, [page_navigation(old.region)])
  coordinator.region_changed(old)
  let old_ticket = old.ticket()
  let latest = coordinator.begin_update(1, [page_navigation(old.region)])
  let target = settled_mount(coordinator, old.region, 2)
  coordinator.region_changed(target)
  let sequence = coordinator.navigation_sequence
  coordinator.finish_update(0, revision)
  coordinator.finish_region(old, old_ticket)
  assert_true(coordinator.invalidate(old).is_empty())
  assert_eq(coordinator.pending.length(), 1)
  assert_true(coordinator.navigation is Some(_))
  coordinator.finish_update(1, latest)
  coordinator.finish_region(target, { ..target.ticket(), mount_instance: 1, })
  assert_true(coordinator.take_navigation(sequence) is None)
  coordinator.finish_region(target, target.ticket())
  assert_true(coordinator.take_navigation(sequence) is Some(_))
}

///|
test "unmount cancels its navigation and cannot transfer it to a replacement mount" {
  let coordinator = Coordinator::new()
  let target = settled_mount(coordinator, File("target.mbt"), 1)
  let revision = coordinator.begin_update(0, [page_navigation(target.region)])
  let sequence = coordinator.navigation_sequence
  coordinator.region_changed(target)
  assert_true(coordinator.invalidate(target).is_empty())
  assert_true(coordinator.pending.is_empty())
  let _replacement = settled_mount(coordinator, target.region, 2)
  coordinator.finish_update(0, revision)
  coordinator.finish_region(target, target.ticket())
  assert_true(coordinator.navigation is None)
  assert_true(coordinator.take_navigation(sequence) is None)
}

///|
test "route changes cancel navigation before central commit and keep durable region cleanup" {
  let coordinator = Coordinator::new()
  let target = settled_mount(coordinator, File("target.mbt"), 1)
  let first = coordinator.begin_update(0, [page_navigation(target.region)])
  let sequence = coordinator.navigation_sequence
  coordinator.region_changed(target)
  target.waiting.push(test_waiter(target.ticket(), Continue))
  target.waiting.push(test_waiter(target.ticket(), Cancel))
  let _revision = coordinator.begin_update(1, [])
  assert_true(coordinator.navigation is None)
  assert_true(coordinator.pending.is_empty())
  assert_eq(coordinator.invalidate(target).length(), 1)
  coordinator.finish_update(0, first)
  assert_true(coordinator.take_navigation(sequence) is None)
}

///|
test "region actions finish without waiting for other regions or replacing page navigation" {
  let coordinator = Coordinator::new()
  let a = settled_mount(coordinator, File("a.mbt"), 1)
  let b = settled_mount(coordinator, File("b.mbt"), 2)
  let revision = coordinator.begin_update(0, [page_navigation(b.region)])
  let sequence = coordinator.navigation_sequence
  coordinator.region_changed(a)
  coordinator.region_changed(b)
  coordinator.wait_for(0, test_waiter(a.ticket(), Continue).action)
  assert_eq(a.waiting.length(), 1)
  let latest = coordinator.begin_update(0, [
    test_waiter(a.ticket(), Cancel).action,
  ])
  assert_eq(coordinator.navigation_sequence, sequence)
  coordinator.finish_update(0, revision)
  coordinator.finish_update(0, latest)
  assert_eq(a.finish(a.ticket()).length(), 1)
  coordinator.finish_region(a, a.ticket())
  assert_true(coordinator.take_navigation(sequence) is None)
  coordinator.finish_region(b, b.ticket())
  assert_true(coordinator.take_navigation(sequence) is Some(_))
}

///|
test "navigation rechecks its target instance immediately before execution" {
  let coordinator = Coordinator::new()
  let target = settled_mount(coordinator, File("target.mbt"), 1)
  let revision = coordinator.begin_update(0, [page_navigation(target.region)])
  let sequence = coordinator.navigation_sequence
  coordinator.finish_update(0, revision)
  let _replacement = settled_mount(coordinator, target.region, 2)
  assert_true(coordinator.take_navigation(sequence) is None)
  assert_true(coordinator.navigation is None)
}
