///|
// Retain only the current hyperlink projection, never a model or RangeState.
fn Coordinator::configure_range(
  self : Coordinator,
  model : @application.Model,
) -> Unit {
  let path = match (model.route, model.range) {
    (Some(reference), Some(state)) =>
      @application.range_selected_path(reference, state)
    _ => None
  }
  self.range_target = (model.generation, path)
  if self.mounts.get(RangePanel) is Some(mount) {
    self.sync_range_link(mount)
  }
}

///|
fn Coordinator::range_href(self : Coordinator, mount : Mount) -> String? {
  let (generation, path) = self.range_target
  if mount.alive &&
    mount.generation == self.generation &&
    mount.generation == generation {
    path
  } else {
    None
  }
}

///|
fn write_range_href(link : @dom.Element, path : String?) -> Unit {
  match path {
    Some(path) => {
      if link.get_attribute("href") != Some(path) {
        link.set_attribute("href", path)
      }
      link.remove_attribute("aria-disabled")
    }
    None => {
      link.remove_attribute("href")
      link.set_attribute("aria-disabled", "true")
    }
  }
}

///|
fn sync_range_root(root : @dom.Element, path : String?) -> Unit {
  if root.query_selector(".range-selector a.range-apply") is Some(link) {
    write_range_href(link, path)
  }
}

///|
fn Coordinator::sync_range_link(self : Coordinator, mount : Mount) -> Unit {
  if mount.region is RangePanel &&
    @browser.element(mount.host + "-root") is Some(root) {
    sync_range_root(root, self.range_href(mount))
  }
}

///|
fn Coordinator::install_range_link(self : Coordinator, mount : Mount) -> Unit {
  guard mount.region is RangePanel &&
    mount.input is Some(RangePanel(input)) &&
    input.reference.target is PullRequest(_) &&
    mount.dispose_range_link is None &&
    @browser.element(mount.host + "-root") is Some(root) else {
    return
  }
  let events = [
    "pointerdown", "click", "auxclick", "contextmenu", "keydown", "dragstart",
  ]
  let activate : @dom.Listener = event => {
    guard event.target().to_element() is Some(target) &&
      target.closest(".range-selector a.range-apply") is Some(link) &&
      root.contains(link.as_node()) else {
      return
    }
    let path = self.range_href(mount)
    write_range_href(link, path)
    if path is None {
      let event_type : String = @browser.event_property(event, "type")
      if event_type == "keydown" {
        let key : String = @browser.event_property(event, "key")
        if key != "Enter" {
          return
        }
      }
      event.prevent_default()
      event.stop_immediate_propagation()
    }
  }
  for event in events {
    root.add_event_listener_with_options(event, activate, capture=true)
  }
  mount.dispose_range_link = Some(() => {
    // The root may already be detached from the document at subscription unload.
    sync_range_root(root, None)
    for event in events {
      root.remove_event_listener_with_options(event, activate, capture=true)
    }
  })
}
