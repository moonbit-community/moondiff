///|
fn rebase_merge_in_titlebar(main : @dom.Element, title_bottom : Double) -> Bool {
  main
  .query_selector(".pull-merge-card")
  .map(card => card.get_bounding_client_rect().get_bottom() <= title_bottom)
  .unwrap_or(false)
}

///|
fn place_rebase_merge(main : @dom.Element, in_titlebar : Bool) -> Unit {
  let attribute = "data-rebase-in-titlebar"
  guard main.has_attribute(attribute) != in_titlebar else { return }
  let card = ".pull-merge-card .rebase-merge-button"
  let title = ".change-titlebar .rebase-merge-button"
  let source = main.query_selector(if in_titlebar { card } else { title })
  let focused = match (source, @dom.document().get_active_element()) {
    (Some(source), Some(active)) => @browser.same(source, active)
    _ => false
  }
  // Visibility preserves both boxes and excludes the hidden button from focus
  // and the accessibility tree, without changing the measured threshold.
  if in_titlebar {
    main.set_attribute(attribute, "true")
  } else {
    main.remove_attribute(attribute)
  }
  if focused &&
    main.query_selector(if in_titlebar { title } else { card }) is Some(target) {
    @browser.focus(target)
  }
}
