///|
fn test_mount() -> Mount {
  {
    generation: 4,
    instance: 12,
    region: File("a.mbt"),
    host: "test",
    alive: true,
    mounted: true,
    revision: 3,
    committed: 0,
    input: None,
    cache: Some(@view.FileDerivation::new()),
    app: None,
    scheduler: None,
    waiting: [],
    dispose_layout: None,
  }
}

///|
fn test_waiter(
  ticket : CommitTicket,
  navigation : @application.NavigationPolicy,
) -> Waiting {
  {
    ticket,
    action: {
      target: File("a.mbt"),
      scope: Region,
      command: @rabbita.none,
      navigation,
    },
  }
}

///|
test "commit waits coalesce updates and reject older revisions, generations and mount instances" {
  let mount = test_mount()
  mount.waiting.push(test_waiter({ ..mount.ticket(), revision: 1, }, Cancel))
  mount.waiting.push(test_waiter(mount.ticket(), Continue))
  for
    ticket in [
      { ..mount.ticket(), revision: 2, },
      { ..mount.ticket(), generation: 3, },
      { ..mount.ticket(), mount_instance: 11, },
    ] {
    assert_eq(mount.finish(ticket).length(), 0)
    assert_eq(mount.waiting.length(), 2)
    assert_eq(mount.committed, 0)
  }
  assert_eq(mount.finish(mount.ticket()).length(), 2)
  assert_eq(mount.committed, 3)
  assert_true(mount.waiting.is_empty())
  assert_true(mount.finish(mount.ticket()).is_empty())
}

///|
test "invalidation cancels UI waits, preserves durable operation ownership, and drops file caches" {
  let mount = test_mount()
  let old_ticket = mount.ticket()
  mount.waiting.push(test_waiter(old_ticket, Cancel))
  mount.waiting.push(test_waiter(old_ticket, Continue))
  assert_eq(mount.invalidate().length(), 1)
  assert_false(mount.alive)
  assert_true(mount.cache is None)
  assert_true(mount.input is None)
  assert_true(mount.waiting.is_empty())
  assert_false(mount.accepts(old_ticket))
  assert_true(mount.finish(old_ticket).is_empty())
  let replacement = { ..test_mount(), instance: 13, }
  assert_false(replacement.accepts(old_ticket))
}
