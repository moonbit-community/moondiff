///|
struct CommitTicket {
  generation : Int32
  mount_instance : Int32
  revision : Int32
} derive(Eq)

///|
priv struct Waiting {
  ticket : CommitTicket
  action : @application.AfterCommit
}

///|
priv struct Mount {
  generation : Int32
  instance : Int32
  region : @application.Region
  host : String
  mut alive : Bool
  mut mounted : Bool
  mut revision : Int32
  mut committed : Int32
  mut input : @view.RegionInput?
  mut cache : @view.FileDerivation?
  mut app : @rabbita.App?
  mut scheduler : &@cmd.Scheduler?
  mut paint_scheduler : &@cmd.Scheduler?
  waiting : Array[Waiting]
  mut dispose_layout : (() -> Unit)?
  mut dispose_range_link : (() -> Unit)?
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
      coordinator.editor.dispose(mount.host)
      if mount.region is FileTree {
        @view.dispose_file_tree_resize()
      }
      remove_host(mount.host)
      mount.app = None
      mount.scheduler = None
      mount.paint_scheduler = None
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
  } else {
    // BrowserHost evaluates the initial projection before draining init commands.
    self.early_commands.push(command)
  }
}

///|
fn Coordinator::attach(self : Coordinator, scheduler : &@cmd.Scheduler) -> Unit {
  self.scheduler = Some(scheduler)
  let commands = self.early_commands
  self.early_commands = []
  scheduler.add(@cmd.batch(commands))
}

///|
fn Coordinator::wait_for(
  self : Coordinator,
  generation : Int32,
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
  // A superseded paint can still write its old href. Reconcile even when its
  // commit ticket is no longer current.
  self.sync_range_link(mount)
  guard self.generation == ticket.generation && mount.accepts(ticket) else {
    return
  }
  if mount.dispose_layout is None {
    mount.dispose_layout = Some(
      self.layout.observe(mount.host, mount.region.key()),
    )
  }
  // Restore interaction in the same commit, before another input event can
  // change the new editor. Only geometry-dependent actions wait for layout.
  if mount.input is Some(input) {
    self.editor.restore(mount.host, input.draft_id())
  }
  self.layout.invalidate(mount.host)
  self.layout.after(() => self.finish_region(mount, ticket))
}

///|
fn region_component(
  coordinator : Coordinator,
  generation : Int32,
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
    paint_scheduler: None,
    waiting: [],
    dispose_layout: None,
    dispose_range_link: None,
  }
  coordinator.mounts[region] = mount
  @metrics.active("mounts", 1)
  let content : Ref[@rabbita.Val[@rabbita.Html]?] = Ref(None)
  // The assoc branch owns state and subscriptions. The mounted app has its own
  // BrowserHost, so acquire its scheduler through a private DOM event bridge.
  // This keeps regional painting independent without moving state out of the
  // branch's cleanup scope.
  let app = @rabbita.new(() => {
    let bridge = @html.div(
      id=mount.host + "-scheduler",
      hidden=true,
      attrs=@html.Attrs::build().on_click(_ => {
        @cmd.custom_cmd(scheduler => {
          guard mount.alive && mount.paint_scheduler is None else { return }
          mount.paint_scheduler = Some(scheduler)
          let ticket = mount.ticket()
          scheduler.add(
            @cmd.custom_cmd(
              kind=@cmd.after_render,
              once(() => coordinator.committed(mount, ticket)),
            ),
          )
        })
      }),
      @html.nothing,
    )
    content.val.unwrap().map(html => @html.fragment([bridge, html]))
  })
  let (revision, refresh) = @rabbita.create_state_with_init(
    init=_ => {
      (0, @cmd.custom_cmd(scheduler => mount.scheduler = Some(scheduler)))
    },
    update=(_, revision : Int32, _) => {
      let ticket = { ..mount.ticket(), revision, }
      (
        revision,
        @cmd.custom_cmd(_ => {
          if mount.paint_scheduler is Some(scheduler) {
            scheduler.add(
              @cmd.custom_cmd(
                kind=@cmd.after_render,
                once(() => coordinator.committed(mount, ticket)),
              ),
            )
          }
        }),
      )
    },
    subscriptions=(_, _) => {
      @sub.custom_sub(
        "region-lifetime",
        Local,
        Lifetime(coordinator, mount),
        SubLoader(lifetime_loader),
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
            create_mount_root(mount.host)
            coordinator.install_range_link(mount)
            app.mount(mount.host + "-root")
            connect_paint_scheduler(mount.host)
          }
        }),
      ),
    )
    { region, id: mount.host, }
  })
}

///|
fn host_connected(id : String) -> Bool {
  @browser.element(id).map(el => el.get_is_connected()).unwrap_or(false)
}

///|
fn connect_paint_scheduler(id : String) -> Unit {
  @browser.element(id + "-scheduler")
  .unwrap()
  .dispatch_event(@browser.mouse_click())
}

///|
fn remove_host(id : String) -> Unit {
  if @browser.element(id + "-root") is Some(root) {
    @browser.remove(root)
  }
}

///|
fn create_mount_root(id : String) -> Unit {
  let root = @dom.document().create_element("div")
  root.set_attribute("id", id + "-root")
  root.set_attribute("class", "render-region")
  @browser.element(id).unwrap().append_child(root.as_node())
}

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
  @application.discard_comment_body_region(self.generation, self.region)
  if self.dispose_range_link is Some(dispose) {
    dispose()
  }
  self.dispose_range_link = None
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
