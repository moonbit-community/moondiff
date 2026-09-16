///|
struct CommitTicket {
  generation : Int
  mount_instance : Int
  revision : Int
} derive(Eq)

///|
priv struct Waiting {
  ticket : CommitTicket
  action : @application.AfterCommit
}

///|
priv struct Mount {
  generation : Int
  instance : Int
  region : @application.Region
  host : String
  mut alive : Bool
  mut mounted : Bool
  mut revision : Int
  mut committed : Int
  mut input : @view.RegionInput?
  mut cache : @view.FileDerivation?
  mut app : @rabbita.App?
  mut scheduler : &@cmd.Scheduler?
  waiting : Array[Waiting]
  mut dispose_layout : (() -> Unit)?
}

///|
fn Mount::ticket(self : Mount) -> CommitTicket {
  {
    generation: self.generation,
    mount_instance: self.instance,
    revision: self.revision,
  }
}

///|
fn Mount::accepts(self : Mount, ticket : CommitTicket) -> Bool {
  self.alive &&
  self.generation == ticket.generation &&
  self.instance == ticket.mount_instance &&
  self.revision == ticket.revision
}

///|
priv suberror Lifetime {
  Lifetime(Coordinator, Mount)
}

///|
fn lifetime_loader(
  payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is Lifetime(coordinator, mount) else { return None }
  @metrics.active("subscriptions", 1)
  @metrics.active("stores", 1)
  Some({
    unload: _ => {
      let remaining = coordinator.invalidate(mount)
      if mount.dispose_layout is Some(dispose) {
        dispose()
      }
      mount.dispose_layout = None
      dispose_editor(mount.host)
      remove_host(mount.host)
      mount.app = None
      mount.scheduler = None
      @metrics.active("mounts", -1)
      @metrics.active("subscriptions", -1)
      @metrics.active("stores", -1)
      for command in remaining {
        coordinator.run(command)
      }
      coordinator.flush_navigation()
    },
    update_tagger: _ => (),
  })
}

///|
fn Coordinator::run(self : Coordinator, command : @rabbita.Cmd) -> Unit {
  if self.scheduler is Some(scheduler) {
    scheduler.add(command)
  }
}

///|
fn Coordinator::wait_for(
  self : Coordinator,
  generation : Int,
  action : @application.AfterCommit,
) -> Unit {
  if generation != self.generation {
    if action.navigation is Continue {
      self.run(action.command)
    }
    return
  }
  guard self.mounts.get(action.target) is Some(mount) &&
    mount.alive &&
    mount.generation == generation else {
    if action.navigation is Continue {
      self.run(action.command)
    }
    return
  }
  if mount.committed == mount.revision {
    self.run(action.command)
  } else {
    mount.waiting.push({ ticket: mount.ticket(), action, })
  }
}

///|
fn Coordinator::committed(
  self : Coordinator,
  mount : Mount,
  ticket : CommitTicket,
) -> Unit {
  guard self.generation == ticket.generation && mount.accepts(ticket) else {
    return
  }
  if mount.dispose_layout is None {
    mount.dispose_layout = Some(observe_layout(mount.host, mount.region.key()))
  }
  // Restore interaction in the same commit, before another input event can
  // change the new editor. Only geometry-dependent actions wait for layout.
  if mount.input is Some(input) {
    restore_editor(mount.host, input.draft_id())
  }
  invalidate_layout(mount.host)
  after_layout(() => self.finish_region(mount, ticket))
}

///|
fn region_component(
  coordinator : Coordinator,
  generation : Int,
  region : @application.Region,
  input : @rabbita.Val[@view.RegionInput],
  emit : @rabbita.Emit[@application.Msg],
) -> @rabbita.Val[@view.MountHost] {
  coordinator.serial += 1
  let mount : Mount = {
    generation,
    instance: coordinator.serial,
    region,
    host: "render-region-\{coordinator.serial}",
    alive: true,
    mounted: false,
    revision: 0,
    committed: -1,
    input: None,
    cache: Some(@view.FileDerivation::new()),
    app: None,
    scheduler: None,
    waiting: [],
    dispose_layout: None,
  }
  coordinator.mounts[region] = mount
  @metrics.active("mounts", 1)
  let content : Ref[@rabbita.Val[@rabbita.Html]?] = Ref(None)
  // Set Rabbita's public app construction context before creating region state.
  // The assoc branch still owns that state's cleanup scope.
  let app = @rabbita.new(() => content.val.unwrap())
  let (revision, refresh) = @rabbita.create_state_with_init(
    init=_ => {
      (0, @cmd.custom_cmd(scheduler => mount.scheduler = Some(scheduler)))
    },
    update=(_, revision : Int, _) => {
      let ticket = { ..mount.ticket(), revision, }
      (
        revision,
        @cmd.custom_cmd(
          kind=@cmd.after_render,
          once(() => coordinator.committed(mount, ticket)),
        ),
      )
    },
    subscriptions=(_, _) => {
      @sub.custom_sub(
        "region-lifetime",
        Local,
        Lifetime(coordinator, mount),
        @sub.SubLoader(lifetime_loader),
      )
    },
  )
  content.val = Some(
    revision.map(_ => {
      guard mount.alive &&
        mount.input is Some(input) &&
        mount.cache is Some(cache) else {
        return @html.nothing
      }
      @view.region_view(input, emit, cache)
    }),
  )
  mount.app = Some(app)
  input.map(input => {
    mount.input = Some(input)
    coordinator.region_changed(mount)
    coordinator.run(
      @cmd.custom_cmd(
        kind=@cmd.after_render,
        once(() => {
          guard mount.alive &&
            coordinator.generation == mount.generation &&
            mount.scheduler is Some(scheduler) else {
            return
          }
          if mount.mounted {
            scheduler.add(refresh(mount.revision))
          } else if mount.app is Some(app) && host_connected(mount.host) {
            mount.mounted = true
            let ticket = mount.ticket()
            scheduler.run_effect(
              @cmd.after_render,
              once(() => coordinator.committed(mount, ticket)),
            )
            create_mount_root(mount.host)
            app.mount(mount.host + "-root")
          }
        }),
      ),
    )
    @view.MountHost::{ region, id: mount.host, }
  })
}

///|
extern "js" fn host_connected(id : String) -> Bool = "id => !!document.getElementById(id)?.isConnected"

///|
extern "js" fn remove_host(id : String) -> Unit = "id => document.getElementById(id + '-root')?.remove()"

///|
extern "js" fn create_mount_root(id : String) -> Unit =
  #| id => {
  #|   const root = document.createElement('div');
  #|   root.id = id + '-root'; root.className = 'render-region';
  #|   document.getElementById(id).appendChild(root);
  #| }

///|
fn Mount::finish(self : Mount, ticket : CommitTicket) -> Array[@rabbita.Cmd] {
  guard self.accepts(ticket) else { return [] }
  self.committed = ticket.revision
  let commands = self.waiting.filter_map(item => {
    if item.ticket.generation == ticket.generation &&
      item.ticket.mount_instance == ticket.mount_instance &&
      item.ticket.revision <= ticket.revision {
      Some(item.action.command)
    } else {
      None
    }
  })
  self.waiting.clear()
  commands
}

///|
fn Mount::invalidate(self : Mount) -> Array[@rabbita.Cmd] {
  self.alive = false
  self.input = None
  self.cache = None
  let durable = self.waiting.filter_map(item => {
    if item.action.navigation is Continue {
      Some(item.action.command)
    } else {
      None
    }
  })
  self.waiting.clear()
  durable
}
