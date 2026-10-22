///|
priv struct EditorRecord {
  host : String
  node : @dom.Element
  mut start : Int32
  mut end : Int32
  mut direction : String
  mut top : Double
}

///|
fn EditorRecord::capture(self : EditorRecord) -> Unit {
  self.start = @browser.selection_start(self.node)
  self.end = @browser.selection_end(self.node)
  self.direction = @browser.selection_direction(self.node)
  self.top = self.node.get_scroll_top()
}

///|
priv struct EditorState {
  records : Map[String, EditorRecord]
  mut active : String
  mut visible : Bool
  mut generation : Int32
  mut focus_intent : Bool
  mut stop_listening : (() -> Unit)?
}

///|
fn EditorState::new() -> EditorState {
  let state : EditorState = {
    records: {},
    active: "",
    visible: false,
    generation: 0,
    focus_intent: false,
    stop_listening: None,
  }
  state.publish()
  state
}

///|
fn EditorState::publish(self : EditorState) -> Unit {
  @metrics.state("editor", "records", self.records.length())
  @metrics.state("editor", "active", self.active)
  @metrics.state("editor", "listening", self.stop_listening is Some(_))
}

///|
fn EditorState::stop(self : EditorState) -> Unit {
  self.focus_intent = false
  if self.stop_listening is Some(stop) {
    self.stop_listening = None
    stop()
  }
}

///|
// Capture at the event boundary. A detached source editor must retain its snapshot.
fn EditorState::capture(self : EditorState) -> Unit {
  guard self.visible &&
    self.records.get(self.active) is Some(saved) &&
    saved.node.get_is_connected() else {
    return
  }
  let focused = @dom.document()
    .get_active_element()
    .map(active => @browser.same(active, saved.node))
    .unwrap_or(false)
  if !focused {
    self.focus_intent = false
  }
  saved.capture()
}

///|
fn EditorState::restore(self : EditorState, host : String, id : String) -> Unit {
  guard self.visible &&
    !id.is_empty() &&
    id == self.active &&
    @browser.element(host) is Some(root) &&
    root.query_selector("textarea[data-draft-id]") is Some(el) &&
    el.get_is_connected() &&
    el.get_attribute("data-draft-id") == Some(id) else {
    return
  }
  let saved = self.records.get(id)
  let record : EditorRecord = {
    host,
    node: el,
    start: 0,
    end: 0,
    direction: "none",
    top: 0.0,
  }
  // Register before focus(), so focusin identifies the replacement correctly.
  self.records[id] = record
  let replaced = saved
    .map(saved => !@browser.same(saved.node, el))
    .unwrap_or(true)
  if self.focus_intent && replaced {
    @browser.focus(el)
  }
  if saved is Some(saved) && replaced {
    @browser.select_range(el, saved.start, saved.end, saved.direction)
    el.set_scroll_top(saved.top)
  }
  record.capture()
  self.publish()
}

///|
fn EditorState::dispose(self : EditorState, host : String) -> Unit {
  let keys = self.records
    .iter()
    .filter(entry => entry.1.host == host)
    .map(entry => entry.0)
    .collect()
  for key in keys {
    self.records.remove(key)
    if key == self.active {
      self.stop()
    }
  }
  self.publish()
}

///|
fn EditorState::activate(
  self : EditorState,
  id : String,
  visible : Bool,
  generation : Int32,
) -> Unit {
  if id != self.active || generation != self.generation {
    self.records.clear()
    self.focus_intent = id != self.active && !id.is_empty() && visible
  }
  self.active = id
  self.generation = generation
  self.visible = !id.is_empty() && visible
  // Hiding a retained draft must not revive an earlier focus intent.
  if !self.visible {
    self.stop()
  } else if self.stop_listening is None {
    let interact : @dom.Listener = event => {
      self.focus_intent = match
        (event.target().to_element(), self.records.get(self.active)) {
        (Some(target), Some(record)) => @browser.same(target, record.node)
        _ => false
      }
    }
    let document = @dom.document()
    document.add_event_listener_with_options("focusin", interact, capture=true)
    document.add_event_listener_with_options(
      "pointerdown",
      interact,
      capture=true,
    )
    self.stop_listening = Some(() => {
      document.remove_event_listener_with_options(
        "focusin",
        interact,
        capture=true,
      )
      document.remove_event_listener_with_options(
        "pointerdown",
        interact,
        capture=true,
      )
    })
  }
  self.publish()
}
