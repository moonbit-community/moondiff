///|
test "range hyperlink projection rejects retired mounts and generations" {
  let coordinator = Coordinator::new()
  let mount = { ..test_mount(), region: RangePanel, }
  coordinator.generation = mount.generation
  coordinator.range_target = (mount.generation, Some("/selected"))
  assert_eq(coordinator.range_href(mount), Some("/selected"))
  coordinator.range_target = (mount.generation, Some("/new-selection"))
  assert_eq(coordinator.range_href(mount), Some("/new-selection"))
  coordinator.range_target = (mount.generation, None)
  assert_true(coordinator.range_href(mount) is None)
  coordinator.range_target = (mount.generation + 1, Some("/next-page"))
  assert_true(coordinator.range_href(mount) is None)
  coordinator.range_target = (mount.generation, Some("/selected"))
  coordinator.generation += 1
  assert_true(coordinator.range_href(mount) is None)
  coordinator.generation = mount.generation
  ignore(mount.invalidate())
  assert_true(coordinator.range_href(mount) is None)
}

///|
test "range mount disposal runs exactly once" {
  let mount = { ..test_mount(), region: RangePanel, }
  let disposed = Ref(0)
  mount.dispose_range_link = Some(() => disposed.val += 1)
  ignore(mount.invalidate())
  ignore(mount.invalidate())
  assert_eq(disposed.val, 1)
  assert_true(mount.dispose_range_link is None)
}
