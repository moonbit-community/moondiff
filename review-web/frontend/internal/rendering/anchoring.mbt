///|
priv enum AnchorOwner {
  History
  Reading
} derive(Eq, Hash)

///|
priv struct NativeAnchoring {
  owners : Map[AnchorOwner, Unit]
  mut saved : (@dom.Element, String, String)?
}

///|
fn NativeAnchoring::new() -> NativeAnchoring {
  { owners: {}, saved: None, }
}

///|
fn NativeAnchoring::acquire(
  self : NativeAnchoring,
  owner : AnchorOwner,
) -> Unit {
  if self.owners.contains(owner) {
    return
  }
  self.owners[owner] = ()
  guard self.saved is None && @browser.has_window() else { return }
  let page = @dom.document().get_document_element().unwrap()
  let style = @browser.style(page)
  self.saved = Some(
    (
      page,
      style.get_property_value("overflow-anchor"),
      style.get_property_priority("overflow-anchor"),
    ),
  )
  style.set_property_with_priority("overflow-anchor", "none", "important")
}

///|
fn NativeAnchoring::release(
  self : NativeAnchoring,
  owner : AnchorOwner,
) -> Unit {
  self.owners.remove(owner)
  if self.owners.is_empty() && self.saved is Some((page, value, priority)) {
    self.saved = None
    let style = @browser.style(page)
    if value.is_empty() {
      ignore(style.remove_property("overflow-anchor"))
    } else {
      style.set_property_with_priority("overflow-anchor", value, priority)
    }
  }
}
