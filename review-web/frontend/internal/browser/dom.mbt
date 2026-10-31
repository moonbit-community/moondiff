///|
pub fn element(id : String) -> @dom.Element? {
  @dom.document().get_element_by_id(id).to_option()
}

///|
pub fn focus(element : @dom.Element) -> Unit {
  if element.to_html_element() is Some(html) {
    html.focus_with_options(prevent_scroll=true)
  }
}

///|
pub fn style(element : @dom.Element) -> @dom.CSSStyleDeclaration {
  element.to_html_element().unwrap().get_style()
}

///|
pub fn[T] property(element : @dom.Element, name : String) -> T {
  @dom.Element::from(element).get_with_string(name)
}

///|
pub fn[T] set_property(
  element : @dom.Element,
  name : String,
  value : T,
) -> Unit {
  @dom.Element::from(element).set_with_string(name, value)
}

///|
pub fn current_element(
  target : @js.Nullable[@dom.EventTarget],
) -> @dom.Element? {
  if target.to_option() is Some(target) {
    target.to_element()
  } else {
    None
  }
}

///|
pub fn same(a : @dom.Element, b : @dom.Element) -> Bool {
  a.is_same_node(b.as_node())
}

///|
pub fn click(element : @dom.Element) -> Unit {
  if element.to_html_element() is Some(html) {
    html.click()
  }
}

///|
pub fn remove(element : @dom.Element) -> Unit {
  if element.get_parent_node().to_option() is Some(parent) {
    parent.remove_child(element.as_node())
  }
}

///|
pub fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
pub extern "js" fn has_focus() -> Bool = "() => document.hasFocus()"

///|
pub extern "js" fn has_window() -> Bool = "() => !!globalThis.window?.location"

///|
pub extern "js" fn resolve_url(url : String) -> String = "url => new URL(url, location.href).href"

///|
pub extern "js" fn parse_float(value : String) -> Double = "value => parseFloat(value)"

///|
pub extern "js" fn selection_start(element : @dom.Element) -> Int32 = "el => el.selectionStart"

///|
pub extern "js" fn selection_end(element : @dom.Element) -> Int32 = "el => el.selectionEnd"

///|
pub extern "js" fn selection_direction(element : @dom.Element) -> String = "el => el.selectionDirection"

///|
pub extern "js" fn select_range(
  element : @dom.Element,
  start : Int32,
  end : Int32,
  direction : String,
) -> Unit =
  #| (el, start, end, direction) => el.setSelectionRange(start, end, direction)

///|
pub fn[T] event_property(event : @dom.Event, name : String) -> T {
  @dom.Event::from(event).get_with_string(name)
}

///|
pub extern "js" fn mouse_click() -> @dom.Event = "() => new MouseEvent('click')"

///|
pub fn fragment_target(href : String) -> @dom.Element? {
  fragment_target_native(href).to_option()
}

///|
extern "js" fn fragment_target_native(
  href : String,
) -> @js.Nullable[@dom.Element] =
  #| href => {
  #|   if (!href.startsWith('#')) return null;
  #|   try { return document.getElementById(decodeURIComponent(href.slice(1))); }
  #|   catch { return null; }
  #| }

///|
pub extern "js" fn navigate_fragment(id : String) -> Unit =
  #| id => { location.hash = encodeURIComponent(id); }

///|
pub extern "js" fn intersection_observer(
  callback : (
    FixedArray[@dom.IntersectionObserverEntry],
    @dom.IntersectionObserver,
  ) -> Unit,
  margin : String,
) -> @dom.IntersectionObserver = "(callback, rootMargin) => new IntersectionObserver(callback, { rootMargin })"

///|
pub extern "js" fn mutation_added_nodes(
  record : @dom.MutationRecord,
) -> FixedArray[@dom.Node] = "record => Array.from(record.addedNodes)"

///|
pub extern "js" fn mutation_has_removed_nodes(
  record : @dom.MutationRecord,
) -> Bool = "record => record.removedNodes.length > 0"
