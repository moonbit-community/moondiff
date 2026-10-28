///|
priv struct LayoutRecord {
  host : @dom.Element
  mut alive : Bool
  prepare : () -> Unit
  read : () -> Array[Double]
  write : (Array[Double]) -> Unit
}

///|
priv struct LayoutState {
  dirty : Map[String, LayoutRecord]
  records : Map[String, LayoutRecord]
  mut callbacks : Array[() -> Unit]
  mut frame : Double
  mut revision : Int32
}

///|
fn LayoutState::new() -> LayoutState {
  let state : LayoutState = {
    dirty: {},
    records: {},
    callbacks: [],
    frame: 0.0,
    revision: 0,
  }
  state.publish()
  state
}

///|
fn LayoutState::publish(self : LayoutState) -> Unit {
  @metrics.state("layout", "frame", self.frame)
  @metrics.state("layout", "dirty", self.dirty.length())
  @metrics.state("layout", "callbacks", self.callbacks.length())
  @metrics.state("layout", "records", self.records.length())
}

///|
// One shared frame reads all dirty geometry, then writes offsets, then runs callbacks.
fn LayoutState::schedule(self : LayoutState) -> Unit {
  self.revision += 1
  if self.frame != 0.0 {
    self.publish()
    return
  }
  self.frame = @dom.window().request_animation_frame(_ => {
    self.frame = 0.0
    let reads : Array[(LayoutRecord, Array[Double])] = []
    for _, record in self.dirty {
      if record.alive && record.host.get_is_connected() {
        reads.push((record, (record.read)()))
      }
    }
    self.dirty.clear()
    for (record, heights) in reads {
      (record.write)(heights)
    }
    let callbacks = self.callbacks
    self.callbacks = []
    self.publish()
    for callback in callbacks {
      callback()
    }
    self.publish()
  })
  self.publish()
}

///|
fn clear_landing(main : @dom.Element?) -> Unit {
  if main is Some(main) {
    @application.clear_navigation_landing(main)
  }
}

///|
fn LayoutState::observe(
  self : LayoutState,
  host_id : String,
  region : String,
) -> () -> Unit {
  let host = @browser.element(host_id).unwrap()
  let main = if host.closest(".change-main") is Some(main) {
    Some(main)
  } else {
    @dom.document().query_selector(".change-main").to_option()
  }
  let elements : Array[@dom.Element] = []
  let mut prepare : () -> Unit = () => ()
  let mut read : () -> Array[Double] = () => {
    elements.map(el => el.get_bounding_client_rect().get_height())
  }
  let mut write : (Array[Double]) -> Unit = _ => ()
  if region.has_prefix("file:") {
    if host.query_selector(".file-card") is Some(file) &&
      file.query_selector(".file-heading") is Some(heading) {
      elements.push(heading)
      elements.push(file)
      prepare = () => file.remove_attribute("data-render-contained")
      read = () => {
        let style = @dom.window().get_computed_style(file)
        let mut edges = 0.0
        // Intrinsic block-size substitutes content, not border or padding.
        for
          property in [
            "border-top-width", "border-bottom-width", "padding-top", "padding-bottom",
          ] {
          let number = @browser.parse_float(style[property])
          if !number.is_nan() {
            edges += number
          }
        }
        [
          heading.get_bounding_client_rect().get_height(),
          0.0.max(file.get_bounding_client_rect().get_height() - edges),
        ]
      }
      write = heights => {
        @browser.style(file).set_property(
          "--file-heading-inset",
          "\{heights[0]}px",
        )
        if @browser.finite(heights[1]) && heights[1] > 0.0 {
          @browser.style(file).set_property(
            "--file-intrinsic-block-size",
            "\{heights[1]}px",
          )
          file.set_attribute("data-render-contained", "true")
        }
        clear_landing(main)
      }
    }
  } else if region == "toolbar" {
    if host.query_selector(".hero-workspace") is Some(toolbar) {
      let workspace = host.closest(".workspace").unwrap()
      elements.push(toolbar)
      write = heights => {
        @browser.style(workspace).set_property(
          "--toolbar-inset",
          "\{heights[0]}px",
        )
      }
    }
  } else if region == "navigation" && main is Some(main) {
    let title = host.closest(".change-titlebar").unwrap()
    elements.push(title)
    elements.push(main)
    write = heights => {
      @browser.style(main).set_property(
        "--change-title-height",
        "\{heights[0]}px",
      )
      @application.clear_navigation_landing(main)
    }
  }
  let bodies : CommentBodies = { host, entries: [], }
  let observed : Ref[@dom.ResizeObserver?] = Ref(None)
  let prepare_region = prepare
  let read_region = read
  let write_region = write
  let body_layouts : Ref[Array[CommentBodyLayout]] = Ref([])
  let record : LayoutRecord = {
    host,
    alive: true,
    prepare: () => {
      prepare_region()
      if observed.val is Some(observer) {
        bodies.sync(observer)
      }
    },
    read: () => {
      let heights = read_region()
      body_layouts.val = bodies.read()
      heights
    },
    write: heights => {
      bodies.write(body_layouts.val)
      body_layouts.val.clear()
      write_region(heights)
    },
  }
  let on_resize : @dom.Listener = _ => {
    clear_landing(main)
    self.dirty[host_id] = record
    self.schedule()
  }
  let on_scroll : @dom.Listener = _ => {
    if main is Some(main) {
      @application.navigation_scrolled(main)
    }
  }
  if region == "navigation" {
    @dom.window().add_event_listener("resize", on_resize)
    @dom.window().add_event_listener_with_options(
      "scroll",
      on_scroll,
      passive=true,
    )
  }
  // The comment overview can commit before its first comments arrive.
  let observer = if elements.is_empty() && region != "discussion" {
    None
  } else {
    let observer = @dom.ResizeObserver::new((_, _) => {
      guard record.alive else { return }
      self.dirty[host_id] = record
      self.schedule()
    })
    observed.val = Some(observer)
    for element in elements {
      observer.observe(element)
    }
    (record.prepare)()
    self.dirty[host_id] = record
    self.schedule()
    @metrics.active("observers", 1)
    Some(observer)
  }
  self.records[host_id] = record
  self.publish()
  () => {
    record.alive = false
    if observer is Some(observer) {
      observer.disconnect()
      @metrics.active("observers", -1)
    }
    observed.val = None
    bodies.entries.clear()
    body_layouts.val.clear()
    if region == "navigation" {
      @dom.window().remove_event_listener("resize", on_resize)
      @dom.window().remove_event_listener("scroll", on_scroll)
    }
    if region == "toolbar" && host.closest(".workspace") is Some(workspace) {
      ignore(@browser.style(workspace).remove_property("--toolbar-inset"))
    }
    self.dirty.remove(host_id)
    self.records.remove(host_id)
    clear_landing(main)
    self.publish()
  }
}

///|
// Include a committed region before acknowledging it, independent of observer delivery.
fn LayoutState::invalidate(self : LayoutState, host : String) -> Unit {
  if self.records.get(host) is Some(record) {
    (record.prepare)()
    self.dirty[host] = record
    self.publish()
  }
}

///|
fn LayoutState::after(self : LayoutState, callback : () -> Unit) -> Unit {
  self.callbacks.push(callback)
  self.schedule()
}
