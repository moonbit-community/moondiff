///|
priv struct PendingNavigation {
  sequence : Int
  generation : Int
  mut mount_instance : Int?
  action : @application.AfterCommit
}

///|
priv struct Coordinator {
  mut scheduler : &@cmd.Scheduler?
  mut generation : Int
  mut serial : Int
  mounts : Map[@application.Region, Mount]
  mut revision : Int
  mut committed : Int
  pending : Map[@application.Region, CommitTicket]
  mut navigation_sequence : Int
  mut navigation : PendingNavigation?
}

///|
fn Coordinator::new() -> Coordinator {
  {
    scheduler: None,
    generation: 0,
    serial: 0,
    mounts: {},
    revision: 0,
    committed: -1,
    pending: {},
    navigation_sequence: 0,
    navigation: None,
  }
}

///|
// Register intent at the event boundary, before any central or regional paint.
// Region inputs are still projected independently by the central graph.
fn Coordinator::begin_update(
  self : Coordinator,
  generation : Int,
  actions : Array[@application.AfterCommit],
) -> Int {
  if self.generation != generation {
    self.generation = generation
    self.navigation = None
    self.pending.clear()
  }
  self.revision += 1
  for action in actions {
    if action.scope is PageLayout {
      self.navigation_sequence += 1
      let mount_instance = match self.mounts.get(action.target) {
        Some(mount) if mount.alive && mount.generation == generation =>
          Some(mount.instance)
        _ => None
      }
      self.navigation = Some({
        sequence: self.navigation_sequence,
        generation,
        mount_instance,
        action,
      })
    }
  }
  self.revision
}

///|
fn Coordinator::finish_update(
  self : Coordinator,
  generation : Int,
  revision : Int,
) -> Unit {
  guard generation == self.generation && revision == self.revision else {
    return
  }
  self.committed = revision
  if self.navigation is Some(navigation) {
    match self.mounts.get(navigation.action.target) {
      Some(mount) if mount.alive && mount.generation == generation =>
        match navigation.mount_instance {
          None => navigation.mount_instance = Some(mount.instance)
          Some(instance) if instance != mount.instance => self.navigation = None
          _ => ()
        }
      _ => self.navigation = None
    }
  }
  self.flush_navigation()
}

///|
fn Coordinator::region_changed(self : Coordinator, mount : Mount) -> Unit {
  mount.revision += 1
  self.pending[mount.region] = mount.ticket()
}

///|
// Called only after this commit's measurements and style writes have finished.
fn Coordinator::finish_region(
  self : Coordinator,
  mount : Mount,
  ticket : CommitTicket,
) -> Unit {
  guard self.generation == ticket.generation && mount.accepts(ticket) else {
    return
  }
  let commands = mount.finish(ticket)
  if self.pending.get(mount.region) == Some(ticket) {
    self.pending.remove(mount.region)
  }
  for command in commands {
    self.run(command)
  }
  self.flush_navigation()
}

///|
fn Coordinator::invalidate(
  self : Coordinator,
  mount : Mount,
) -> Array[@rabbita.Cmd] {
  let commands = mount.invalidate()
  if self.mounts.get(mount.region) is Some(current) &&
    current.instance == mount.instance {
    self.mounts.remove(mount.region)
  }
  if self.pending.get(mount.region) is Some(ticket) &&
    ticket.generation == mount.generation &&
    ticket.mount_instance == mount.instance {
    self.pending.remove(mount.region)
  }
  if self.navigation is Some(navigation) &&
    navigation.generation == mount.generation &&
    navigation.action.target == mount.region &&
    (
      navigation.mount_instance is None ||
      navigation.mount_instance == Some(mount.instance)
    ) {
    self.navigation = None
  }
  commands
}

///|
fn Coordinator::take_navigation(
  self : Coordinator,
  sequence : Int,
) -> @rabbita.Cmd? {
  guard self.navigation is Some(navigation) &&
    navigation.sequence == sequence &&
    navigation.generation == self.generation &&
    self.committed == self.revision &&
    self.pending.is_empty() else {
    return None
  }
  guard self.mounts.get(navigation.action.target) is Some(mount) &&
    mount.alive &&
    mount.mounted &&
    mount.generation == navigation.generation &&
    Some(mount.instance) == navigation.mount_instance else {
    self.navigation = None
    return None
  }
  guard mount.committed == mount.revision else { return None }
  self.navigation = None
  Some(navigation.action.command)
}

///|
fn Coordinator::flush_navigation(self : Coordinator) -> Unit {
  guard self.navigation is Some(navigation) &&
    self.committed == self.revision &&
    self.pending.is_empty() else {
    return
  }
  let sequence = navigation.sequence
  self.run(
    @cmd.custom_cmd(
      once(() => {
        // Recheck at command execution too; a newer event or unmount wins.
        if self.take_navigation(sequence) is Some(command) {
          self.run(command)
        }
      }),
    ),
  )
}

///|
fn Coordinator::after_update(
  self : Coordinator,
  generation : Int,
  revision : Int,
  actions : Array[@application.AfterCommit],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(
    kind=@cmd.after_render,
    once(() => {
      for action in actions {
        self.wait_for(generation, action)
      }
      after_layout(() => self.finish_update(generation, revision))
    }),
  )
}
