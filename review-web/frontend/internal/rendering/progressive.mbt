///|
priv struct ProgressiveState {
  mut generation : Int32
  mut candidates : Array[(Int32, String)]
  mut enabled : Bool
  mut scrolled : Bool
  mut suppressed : Bool
  mut navigation_locked : Bool
  mut scheduled : Bool
  mut targets_dirty : Bool
  mut height : Double
  mut epoch : Int32
  mut observer : @dom.IntersectionObserver?
  targets : Map[String, @dom.Element]
  mut stop : (() -> Unit)?
  mut emit : @rabbita.Emit[@application.Msg]?
  mut anchor : (@dom.Element, Double)?
  anchoring : NativeAnchoring
}

///|
fn ProgressiveState::new(
  anchoring~ : NativeAnchoring = NativeAnchoring::new(),
) -> ProgressiveState {
  {
    generation: -1,
    candidates: [],
    enabled: false,
    scrolled: false,
    suppressed: false,
    navigation_locked: false,
    scheduled: false,
    targets_dirty: true,
    height: 0,
    epoch: 0,
    observer: None,
    targets: {},
    stop: None,
    emit: None,
    anchor: None,
    anchoring,
  }
}

///|
fn ProgressiveState::release_anchoring(self : ProgressiveState) -> Unit {
  self.anchoring.release(History)
}

///|
fn ProgressiveState::hold_anchoring(self : ProgressiveState) -> Unit {
  self.anchoring.acquire(History)
}

///|
fn ProgressiveState::disconnect(self : ProgressiveState) -> Unit {
  self.epoch += 1
  if self.observer is Some(observer) {
    observer.disconnect()
    @metrics.active("observers", -1)
  }
  self.observer = None
  self.targets.clear()
  self.targets_dirty = true
}

///|
fn ProgressiveState::dispose(self : ProgressiveState) -> Unit {
  self.release_anchoring()
  self.disconnect()
  if self.stop is Some(stop) {
    stop()
  }
  self.stop = None
  self.emit = None
  self.candidates = []
  self.anchor = None
  self.scrolled = false
  self.suppressed = false
  self.navigation_locked = false
  @metrics.state("progressive", "targets", 0)
  @metrics.state("progressive", "listening", false)
}

///|
fn Coordinator::configure_progressive(
  self : Coordinator,
  model : @application.Model,
  emit : @rabbita.Emit[@application.Msg],
) -> Unit {
  let state = self.progressive
  let candidates = []
  if model.phase is Showing(view) {
    for index, file in view.files {
      if @application.auto_expand_candidate(model, index) {
        candidates.push((index, file.file.filename))
      }
    }
  }
  if state.generation != model.generation {
    state.dispose()
    state.generation = model.generation
  }
  state.enabled = @application.auto_expand_allowed(model)
  if state.candidates != candidates {
    state.candidates = candidates
    state.targets_dirty = true
  }
  if candidates.is_empty() && !state.anchoring.owners.contains(History) {
    state.dispose()
    return
  }
  state.emit = Some(emit)
  if state.stop is None {
    let scroll : @dom.Listener = _ => {
      guard state.enabled &&
        !state.suppressed &&
        !state.navigation_locked &&
        self.navigation is None else {
        return
      }
      state.scrolled = true
      state.anchor = None
      self.schedule_progressive()
    }
    let resize : @dom.Listener = _ => {
      state.anchor = None
      state.targets_dirty = true
      self.schedule_progressive()
    }
    // Native history/focus restoration can deliver scroll events several frames
    // after its command. Require fresh scrolling input after navigation instead
    // of guessing when those browser events have finished.
    let intent : @dom.Listener = _ => {
      state.release_anchoring()
      state.navigation_locked = false
    }
    let key : @dom.Listener = event => {
      let key : String = @browser.event_property(event, "key")
      if ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "].contains(
          key,
        ) {
        state.release_anchoring()
        state.navigation_locked = false
      }
    }
    let window = @dom.window()
    window.add_event_listener_with_options("scroll", scroll, passive=true)
    window.add_event_listener("resize", resize)
    window.add_event_listener_with_options("wheel", intent, passive=true)
    window.add_event_listener_with_options("touchmove", intent, passive=true)
    window.add_event_listener_with_options("pointerdown", intent, passive=true)
    window.add_event_listener("keydown", key)
    state.stop = Some(() => {
      window.remove_event_listener("scroll", scroll)
      window.remove_event_listener("resize", resize)
      window.remove_event_listener("wheel", intent)
      window.remove_event_listener("touchmove", intent)
      window.remove_event_listener("pointerdown", intent)
      window.remove_event_listener("keydown", key)
    })
    @metrics.state("progressive", "listening", true)
  }
}

///|
fn Coordinator::schedule_progressive(self : Coordinator) -> Unit {
  let state = self.progressive
  guard !state.scheduled &&
    !state.candidates.is_empty() &&
    (state.scrolled || state.targets_dirty) else {
    return
  }
  state.scheduled = true
  self.layout.after(() => {
    state.scheduled = false
    self.check_progressive()
  })
}

///|
fn Coordinator::check_progressive(self : Coordinator) -> Unit {
  let state = self.progressive
  guard !state.candidates.is_empty() &&
    self.committed == self.revision &&
    self.pending.is_empty() else {
    return
  }
  let height = @dom.window().inner_height()
  if state.observer is None || state.height != height {
    state.disconnect()
    state.height = height
    let epoch = state.epoch
    state.observer = Some(
      @browser.intersection_observer(
        (_, _) => if state.epoch == epoch { self.schedule_progressive() },
        "0px 0px \{height}px 0px",
      ),
    )
    @metrics.active("observers", 1)
  }
  if state.targets_dirty {
    state.targets_dirty = false
    let observer = state.observer.unwrap()
    let paths : Map[String, Bool] = Map([])
    for (_, path) in state.candidates {
      paths[path] = true
    }
    for (path, element) in state.targets.iter().collect() {
      if !paths.contains(path) || !element.get_is_connected() {
        observer.unobserve(element)
        state.targets.remove(path)
      }
    }
    for (index, path) in state.candidates {
      if !state.targets.contains(path) &&
        @browser.element("moondiff-file-\{index}") is Some(element) {
        state.targets[path] = element
        observer.observe(element)
      }
    }
    @metrics.state("progressive", "targets", state.targets.length())
  }
  guard state.enabled &&
    state.scrolled &&
    !state.suppressed &&
    !state.navigation_locked &&
    self.navigation is None &&
    self.reading is None &&
    !@dom.document().hidden() else {
    return
  }
  if state.anchor is Some((anchor, top)) {
    state.anchor = None
    if anchor.get_is_connected() {
      let delta = anchor.get_bounding_client_rect().get_top() - top
      if delta.abs() > 0.5 {
        state.suppressed = true
        @browser.scroll_to(@browser.scroll_x(), @browser.scroll_y() + delta)
        self.layout.after(() => state.suppressed = false)
      }
    }
  }
  let selected : Array[String] = []
  for (_, path) in state.candidates {
    if state.targets.get(path) is Some(element) {
      let rect = element.get_bounding_client_rect()
      if in_expansion_range(rect.get_top(), rect.get_bottom(), height) {
        selected.push(path)
        if selected.length() == 2 {
          break
        }
      }
    }
  }
  if selected.is_empty() {
    return
  }
  @metrics.counter("auto_expand_batches", 1)
  @metrics.state("progressive", "batch_size", selected.length())
  state.anchor = reading_anchor()
  if state.emit is Some(emit) {
    for path in selected {
      self.run(emit(Load(AutoExpandFile(state.generation, path))))
    }
  }
}

///|
fn in_expansion_range(top : Double, bottom : Double, height : Double) -> Bool {
  height > 0 && bottom > 0 && top < height * 2
}

///|
fn reading_edge() -> (Double, Double)? {
  guard @dom.document().query_selector(".change-main").to_option() is Some(main) else {
    return None
  }
  let rect = main.get_bounding_client_rect()
  let mut top = 8.0
  for selector in [".hero-workspace", ".change-titlebar"] {
    if @dom.document().query_selector(selector).to_option() is Some(element) {
      top += element.get_bounding_client_rect().get_height()
    }
  }
  Some((rect.get_left() + rect.get_width() / 2, top))
}

///|
fn reading_anchor() -> (@dom.Element, Double)? {
  guard reading_edge() is Some((x, top)) else { return None }
  @dom.document()
  .element_from_point(x, top)
  .bind(element => element.closest(".file-card"))
  .map(element => (element, element.get_bounding_client_rect().get_top()))
}
