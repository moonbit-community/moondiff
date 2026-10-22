///|
priv struct ReadingProtection {
  token : @application.ReadingRecovery
  region : @application.Region
  mount_instance : Int32
  card : @dom.Element
  anchor : @dom.Element
  top : Double
  emit : @rabbita.Emit[@application.Msg]
  stop : () -> Unit
  mut frame : Double
  mut quiet : Int32
  mut revision : Int32
  mut layout_revision : Int32
}

///|
fn Coordinator::end_reading(self : Coordinator, cancelled : Bool) -> Unit {
  guard self.reading is Some(reading) else { return }
  self.reading = None
  reading.token.finished = true
  reading.token.cancelled = reading.token.cancelled || cancelled
  if reading.frame != 0.0 {
    @dom.window().cancel_animation_frame(reading.frame)
  }
  (reading.stop)()
  self.anchoring.release(Reading)
  @metrics.state("reading", "active", false)
  @metrics.state("reading", "listening", false)
  @metrics.state("reading", "frame", 0)
  @metrics.counter(
    if cancelled {
      "reading_cancelled"
    } else {
      "reading_finished"
    },
    1,
  )
  self.run((reading.emit)(Ui(ReadingRecoveryFinished(reading.token.id))))
}

///|
fn Coordinator::configure_reading(
  self : Coordinator,
  token : @application.ReadingRecovery?,
  emit : @rabbita.Emit[@application.Msg],
) -> Unit {
  @metrics.state("reading", "metadata", token is Some(_))
  if self.reading is Some(reading) &&
    (token.map(t => t.id) != Some(reading.token.id) || reading.token.cancelled) {
    self.end_reading(true)
  }
  guard token is Some(token) else { return }
  // Retirement is synchronous too: a queued cleanup message must not leave a
  // window in which another event can recapture this completed token.
  if token.finished {
    self.run(emit(Ui(ReadingRecoveryFinished(token.id))))
    return
  }
  if token.cancelled ||
    token.generation != self.generation ||
    self.navigation is Some(_) {
    token.cancelled = true
    token.finished = true
    self.run(emit(Ui(ReadingRecoveryFinished(token.id))))
    return
  }
  if self.reading is Some(_) {
    @metrics.counter("reading_merged", 1)
  } else {
    guard @browser.has_window() &&
      @browser.scroll_y() > 0 &&
      loaded_reading_anchor() is Some((card, anchor, top)) else {
      // Skipping an empty/unscrolled reading area retires only this round.
      // It must not block a later activation once code becomes readable.
      token.finished = true
      @metrics.state("reading", "active", false)
      @metrics.state("reading", "listening", false)
      @metrics.state("reading", "frame", 0)
      self.run(emit(Ui(ReadingRecoveryFinished(token.id))))
      return
    }
    guard card.get_attribute("data-file-path") is Some(path) &&
      self.mounts.get(File(path)) is Some(mount) &&
      mount.alive &&
      mount.mounted &&
      mount.generation == token.generation else {
      token.cancelled = true
      token.finished = true
      self.run(emit(Ui(ReadingRecoveryFinished(token.id))))
      return
    }
    // Register synchronously, before a regional paint or queued command can run.
    let listener : @dom.Listener = event => {
      let kind : String = @browser.event_property(event, "type")
      let bubbles : Bool = @browser.event_property(event, "bubbles")
      if kind == "click" && !bubbles {
        return
      }
      self.end_reading(true)
    }
    let events = [
      "wheel", "touchstart", "touchmove", "pointerdown", "click", "keydown", "input",
    ]
    let window = @dom.window()
    for event in events {
      window.add_event_listener_with_options(
        event,
        listener,
        capture=true,
        passive=true,
      )
    }
    self.reading = Some({
      token,
      region: File(path),
      mount_instance: mount.instance,
      card,
      anchor,
      top,
      emit,
      stop: () => {
        for event in events {
          window.remove_event_listener_with_options(
            event,
            listener,
            capture=true,
          )
        }
      },
      frame: 0,
      quiet: 0,
      revision: -1,
      layout_revision: -1,
    })
    @metrics.counter("reading_captured", 1)
    @metrics.state("reading", "id", token.id)
    @metrics.state("reading", "top", top)
    @metrics.state(
      "reading",
      "row",
      anchor.get_attribute("data-reading-row").unwrap_or(""),
    )
    @metrics.state("reading", "active", true)
    @metrics.state("reading", "listening", true)
  }
  self.anchoring.acquire(Reading)
  self.schedule_reading()
}

///|
fn loaded_reading_file() -> @dom.Element? {
  if reading_anchor() is Some((anchor, _)) &&
    anchor.query_selector(".diff-scroll table") is Some(_) {
    return Some(anchor)
  }
  // A sign-in modal's backdrop intercepts hit testing over the inert diff.
  // Find only the background card here; row selection is identical in both paths.
  guard @dom.document().query_selector("dialog[open]").to_option() is Some(_) &&
    reading_edge() is Some((_, edge)) else {
    return None
  }
  for anchor in @dom.document().query_selector_all(".file-card.expanded").iter() {
    let rect = anchor.get_bounding_client_rect()
    if rect.get_top() <= edge &&
      rect.get_bottom() > edge &&
      anchor.query_selector(".diff-scroll table") is Some(_) {
      return Some(anchor)
    }
  }
  None
}

///|
fn loaded_reading_anchor() -> (@dom.Element, @dom.Element, Double)? {
  guard loaded_reading_file() is Some(card) && reading_edge() is Some((_, edge)) else {
    return None
  }
  let edge = card
    .query_selector(".file-heading")
    .map(heading => edge.max(heading.get_bounding_client_rect().get_bottom()))
    .unwrap_or(edge)
  let height = @dom.window().inner_height()
  // Query only this file. Hidden layouts and folded sections have no geometry;
  // source rows are ordered by position within each visible table.
  for table in card.query_selector_all(".diff-scroll table").iter() {
    let rect = table.get_bounding_client_rect()
    if rect.get_width() <= 0 ||
      rect.get_height() <= 0 ||
      rect.get_bottom() <= edge ||
      rect.get_top() >= height {
      continue
    }
    let row_edge = table
      .closest(".semantic-section[open]")
      .bind(section => section.query_selector(".semantic-section-title"))
      .map(heading => edge.max(heading.get_bounding_client_rect().get_bottom()))
      .unwrap_or(edge)
    let rows = table.query_selector_all("[data-reading-row]")
    let mut low = 0
    let mut high = rows.length()
    while low < high {
      let middle = low + (high - low) / 2
      let row = rows.item(middle.to_double()).unwrap()
      if row.get_bounding_client_rect().get_top() < row_edge {
        low = middle + 1
      } else {
        high = middle
      }
    }
    if rows.item(low.to_double()).to_option() is Some(row) {
      let rect = row.get_bounding_client_rect()
      if rect.get_height() > 0 && rect.get_top() < height {
        return Some((card, row, rect.get_top()))
      }
    }
  }
  Some((card, card, card.get_bounding_client_rect().get_top()))
}

///|
fn Coordinator::owns_reading(self : Coordinator, id : Int32) -> Bool {
  guard self.reading is Some(reading) else { return false }
  reading.token.id == id &&
  !reading.token.cancelled &&
  !reading.token.finished &&
  reading.token.generation == self.generation &&
  self.navigation is None &&
  self.mounts.get(reading.region) is Some(mount) &&
  mount.alive &&
  mount.mounted &&
  mount.instance == reading.mount_instance &&
  mount.generation == reading.token.generation
}

///|
fn Coordinator::reading_ready(self : Coordinator, id : Int32) -> Bool {
  self.owns_reading(id) &&
  self.committed == self.revision &&
  self.pending.is_empty() &&
  self.layout.dirty.is_empty()
}

///|
fn Coordinator::flush_reading(self : Coordinator) -> Unit {
  guard self.reading is Some(reading) else { return }
  if !self.owns_reading(reading.token.id) ||
    !reading.anchor.get_is_connected() ||
    !reading.card.matches(".file-card.expanded") ||
    reading.card.query_selector(".diff-scroll table") is None ||
    reading.anchor.get_bounding_client_rect().get_height() <= 0 {
    self.end_reading(true)
    return
  }
  guard self.reading_ready(reading.token.id) else { return }
  // The modal owns the inert background's scroll floor and focus. Keep the
  // original baseline for automatic close on success, but do not scroll the
  // page underneath it while the user is reading or tabbing through the dialog.
  if @dom.document().query_selector("dialog[open]").to_option() is Some(_) {
    return
  }
  let delta = reading.anchor.get_bounding_client_rect().get_top() - reading.top
  let page = @dom.document().get_document_element().unwrap()
  let height : Double = @browser.property(page, "scrollHeight")
  let maximum = (height - @dom.window().inner_height()).max(0)
  let target = (@browser.scroll_y() + delta).max(0).min(maximum)
  if (target - @browser.scroll_y()).abs() > 0.5 {
    // Do not turn compensation into progressive expansion or navigation intent.
    self.progressive.suppressed = true
    self.progressive.scrolled = false
    self.progressive.anchor = None
    @browser.scroll_to(@browser.scroll_x(), target)
    self.layout.after(() => self.progressive.suppressed = false)
    @metrics.counter("reading_compensated", 1)
  }
  @metrics.state("reading", "delta", delta)
  @metrics.state(
    "reading",
    "current_top",
    reading.anchor.get_bounding_client_rect().get_top(),
  )
  @metrics.state("reading", "pending", reading.token.pending())
}

///|
fn Coordinator::schedule_reading(self : Coordinator) -> Unit {
  guard @browser.has_window() &&
    self.reading is Some(reading) &&
    reading.frame == 0 else {
    return
  }
  // Capture only the ID and coordinator: old queued frames must not retain nodes.
  let id = reading.token.id
  reading.frame = @dom.window().request_animation_frame(_ => {
    self.reading_frame(id)
  })
  @metrics.state("reading", "frame", reading.frame)
}

///|
fn Coordinator::reading_frame(self : Coordinator, id : Int32) -> Unit {
  guard self.reading is Some(reading) && reading.token.id == id else { return }
  reading.frame = 0
  @metrics.state("reading", "frame", 0)
  self.flush_reading()
  guard self.reading is Some(_) else { return }
  let idle = self.committed == self.revision &&
    self.pending.is_empty() &&
    self.layout.frame == 0 &&
    self.layout.dirty.is_empty() &&
    self.layout.callbacks.is_empty()
  reading.quiet = if idle &&
    reading.revision == self.revision &&
    reading.layout_revision == self.layout.revision {
    reading.quiet + 1
  } else {
    0
  }
  reading.revision = self.revision
  reading.layout_revision = self.layout.revision
  if reading.quiet >= 2 {
    self.anchoring.release(Reading)
    if !reading.token.pending() {
      self.end_reading(false)
    }
    // Network waits keep the baseline, not an animation loop or native-anchor lock.
  } else {
    self.schedule_reading()
  }
}
