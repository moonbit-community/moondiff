///|
// The native popover is in the top layer. Keep positioning compatible with Chrome 116.
fn menu_for(button : @dom.Element) -> @dom.Element? {
  if button.get_parent_element() is Some(parent) {
    parent.query_selector("[role=\"menu\"]")
  } else {
    None
  }
}

///|
fn hide_menu(menu : @dom.Element) -> Unit {
  menu.to_html_element().unwrap().hide_popover()
}

///|
fn focus_menu_button(menu : @dom.Element) -> Unit {
  if menu.get_parent_element() is Some(parent) &&
    parent.query_selector("[aria-haspopup=\"menu\"]") is Some(button) {
    @browser.focus(button)
  }
}

///|
fn toggle_action_menu(event : @dom.MouseEvent) -> Unit {
  event.prevent_default()
  guard @browser.current_element(event.current_target()) is Some(button) &&
    menu_for(button) is Some(menu) else {
    return
  }
  @browser.set_property(button, "popoverTargetElement", menu)
  if menu.matches(":popover-open") {
    hide_menu(menu)
    return
  }
  let rect = button.get_bounding_client_rect()
  let cleanup : Ref[(() -> Unit)?] = Ref(None)
  let stop = () => {
    if cleanup.val is Some(dispose) {
      cleanup.val = None
      dispose()
    }
  }
  let before_toggle : @dom.Listener = event => {
    if (@browser.event_property(event, "newState") : String) == "closed" {
      button.set_attribute("aria-expanded", "false")
      stop()
    }
  }
  let dismiss : @dom.Listener = event => {
    if !menu.get_is_connected() {
      stop()
      return
    }
    if (@browser.event_property(event, "type") : String) == "scroll" &&
      event.target().to_node() is Some(target) &&
      menu.contains(target) {
      return
    }
    let current = button.get_bounding_client_rect()
    if (@browser.event_property(event, "type") : String) == "scroll" &&
      current.get_top() == rect.get_top() &&
      current.get_right() == rect.get_right() {
      return
    }
    hide_menu(menu)
    stop()
  }
  menu.add_event_listener("beforetoggle", before_toggle)
  let window = @dom.window()
  window.add_event_listener_with_options("scroll", dismiss, capture=true)
  window.add_event_listener("resize", dismiss)
  cleanup.val = Some(() => {
    menu.remove_event_listener("beforetoggle", before_toggle)
    window.remove_event_listener_with_options("scroll", dismiss, capture=true)
    window.remove_event_listener("resize", dismiss)
  })
  menu.to_html_element().unwrap().show_popover()
  button.set_attribute("aria-expanded", "true")
  let box = menu.get_bounding_client_rect()
  let left = 8.0.max(
    (rect.get_right() - box.get_width()).min(
      window.inner_width() - box.get_width() - 8.0,
    ),
  )
  let top = if rect.get_bottom() + 4.0 + box.get_height() <=
    window.inner_height() - 8.0 {
    rect.get_bottom() + 4.0
  } else {
    rect.get_top() - box.get_height() - 4.0
  }
  @browser.style(menu).set_property("left", "\{left}px")
  @browser.style(menu).set_property(
    "top",
    "\{8.0.max(top.min(window.inner_height() - box.get_height() - 8.0))}px",
  )
  if menu.query_selector("[role=\"menuitem\"]:not(:disabled)") is Some(item) {
    @browser.focus(item)
  }
}

///|
fn dismiss_action_menu(event : @dom.MouseEvent) -> Unit {
  guard event.target().to_element() is Some(target) &&
    target.closest("[role=\"menuitem\"]:not(:disabled)") is Some(_) &&
    @browser.current_element(event.current_target()) is Some(menu) else {
    return
  }
  hide_menu(menu)
  focus_menu_button(menu)
}

///|
fn action_menu_button_key(event : @dom.KeyboardEvent) -> Unit {
  if event.key() != "ArrowDown" && event.key() != "ArrowUp" {
    return
  }
  event.prevent_default()
  guard @browser.current_element(event.current_target()) is Some(button) &&
    menu_for(button) is Some(menu) else {
    return
  }
  if !menu.matches(":popover-open") {
    @browser.click(button)
  }
  let items = menu
    .query_selector_all("[role=\"menuitem\"]:not(:disabled)")
    .iter()
    .collect()
  let index = if event.key() == "ArrowUp" { items.length() - 1 } else { 0 }
  if items.get(index) is Some(item) {
    @browser.focus(item)
  }
}

///|
fn menu_key_index(key : String, index : Int32, length : Int32) -> Int32? {
  if length == 0 {
    return None
  }
  match key {
    "ArrowDown" => Some((index + 1) % length)
    "ArrowUp" => Some((index + length - 1) % length)
    "Home" => Some(0)
    "End" => Some(length - 1)
    _ => None
  }
}

///|
fn action_menu_key(event : @dom.KeyboardEvent) -> Unit {
  guard @browser.current_element(event.current_target()) is Some(menu) else {
    return
  }
  if event.key() == "Escape" || event.key() == "Tab" {
    if event.key() == "Escape" {
      event.prevent_default()
      event.stop_propagation()
    }
    hide_menu(menu)
    focus_menu_button(menu)
    return
  }
  if event.key() == " " &&
    event.target().to_element() is Some(target) &&
    target.matches("a[role=\"menuitem\"]") {
    event.prevent_default()
    @browser.click(target)
    return
  }
  let items = menu
    .query_selector_all("[role=\"menuitem\"]:not(:disabled)")
    .iter()
    .collect()
  let index = if @dom.document().get_active_element() is Some(active) {
    items.search_by(item => @browser.same(item, active)).unwrap_or(-1)
  } else {
    -1
  }
  guard menu_key_index(event.key(), index, items.length()) is Some(next) else {
    return
  }
  event.prevent_default()
  if items.get(next) is Some(item) {
    @browser.focus(item)
  }
}
