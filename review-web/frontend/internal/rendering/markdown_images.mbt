///|
priv struct ImageLoad {
  image : @dom.Element
  container : @dom.Element
  deadline : Double
  mut timer : Int32
  mut pending : Bool
}

///|
priv struct MarkdownImages {
  root : @dom.Element
  mut loads : Array[ImageLoad]
}

///|
fn MarkdownImages::settle(
  self : MarkdownImages,
  load : ImageLoad,
  success : Bool,
) -> Unit {
  guard load.pending else { return }
  load.pending = false
  @dom.window().clear_timeout(load.timer)
  self.loads = self.loads.filter(entry => {
    !@browser.same(entry.image, load.image)
  })
  let current = self.root.contains(load.image.as_node())
  if success && current && @browser.performance_now() < load.deadline {
    load.image.remove_attribute("hidden")
    if load.container.query_selector(".markdown-image-fallback") is Some(text) {
      text.set_attribute("hidden", "")
    }
    load.container.set_attribute("data-image-state", "loaded")
  } else {
    // Removing src also stops an outstanding request when a node is retired.
    load.image.remove_attribute("src")
    @browser.remove(load.image)
    load.container.set_attribute("data-image-state", "link")
  }
}

///|
fn MarkdownImages::start_image(
  self : MarkdownImages,
  image : @dom.Element,
) -> Unit {
  guard self.root.contains(image.as_node()) &&
    image.get_node_name() == "IMG" &&
    image.get_attribute("data-markdown-src") is Some(src) &&
    image.get_attribute("data-image-started") is None &&
    image.get_parent_element() is Some(container) else {
    return
  }
  image.set_attribute("data-image-started", "")
  container.set_attribute("data-image-state", "pending")
  let load = ImageLoad::{
    image,
    container,
    deadline: @browser.performance_now() + 10000,
    timer: 0,
    pending: true,
  }
  self.loads.push(load)
  load.timer = @dom.window().set_timeout(() => self.settle(load, false), 10000)
  // State, timeout, and capture listeners are ready before a cached image can
  // dispatch load/error. Completion and late callbacks settle each node once.
  image.set_attribute("src", src)
  if image.to_html_image_element() is Some(native) && native.get_complete() {
    self.settle(load, native.get_natural_width() > 0)
  }
}

///|
fn MarkdownImages::scan(self : MarkdownImages, element : @dom.Element) -> Unit {
  self.start_image(element)
  for image in element.query_selector_all("img[data-markdown-src]").iter() {
    self.start_image(image)
  }
}

///|
fn install_markdown_images(root : @dom.Element) -> Unit {
  let state = MarkdownImages::{ root, loads: [], }
  let complete = fn(event : @dom.Event) {
    guard event.target().to_element() is Some(image) else { return }
    if state.loads.iter().find_first(load => @browser.same(load.image, image))
      is Some(load) {
      state.settle(
        load,
        @browser.event_property(event, "type") == "load" &&
        image
        .to_html_image_element()
        .map(native => native.get_natural_width() > 0)
        .unwrap_or(false),
      )
    }
  }
  root.add_event_listener_with_options("load", complete, capture=true)
  root.add_event_listener_with_options("error", complete, capture=true)
  let observer = @dom.MutationObserver::new((records, _) => {
    if records.iter().any(@browser.mutation_has_removed_nodes) {
      // A snapshot can replace all images before the observer runs. Retire old
      // nodes first, without letting their timers affect the replacement nodes.
      for load in state.loads.copy() {
        if !root.contains(load.image.as_node()) {
          state.settle(load, false)
        }
      }
    }
    for record in records {
      for node in @browser.mutation_added_nodes(record) {
        if node.to_element() is Some(element) && root.contains(node) {
          state.scan(element)
        }
      }
    }
  })
  observer.observe(root.as_node(), child_list=true, subtree=true)
  state.scan(root)
}
