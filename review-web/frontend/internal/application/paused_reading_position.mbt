///|
// Auth controls and the rate-limit notice can change height above a loaded file.
// Restore its reading anchor after regional layout commits without moving focus.
fn paused_reading_position(before : Model, next : Model) -> AfterCommit? {
  guard @browser.has_window() &&
    before.generation == next.generation &&
    (before.source_pause is Some(_) || next.source_pause is Some(_)) &&
    (before.source_pause != next.source_pause || before.auth != next.auth) &&
    next.phase is Showing(_) &&
    !next.navigation.restore_position &&
    @browser.scroll_y() > 0 &&
    @dom.document().query_selector(".change-main").to_option() is Some(main) else {
    return None
  }
  let rect = main.get_bounding_client_rect()
  let mut top = 8.0
  for selector in [".hero-workspace", ".change-titlebar"] {
    if @dom.document().query_selector(selector).to_option() is Some(element) {
      top += element.get_bounding_client_rect().get_height()
    }
  }
  guard @dom.document()
    .element_from_point(rect.get_left() + rect.get_width() / 2, top)
    .bind(element => element.closest(".file-card"))
    is Some(anchor) &&
    anchor.query_selector(".diff-scroll table") is Some(_) &&
    anchor.get_attribute("data-file-path") is Some(path) else {
    return None
  }
  let previous_top = anchor.get_bounding_client_rect().get_top()
  Some({
    target: File(path),
    scope: PageLayout,
    navigation: Cancel,
    command: @cmd.custom_cmd(_ => {
      if anchor.get_is_connected() {
        let delta = anchor.get_bounding_client_rect().get_top() - previous_top
        if delta.abs() > 0.5 {
          @browser.scroll_to(@browser.scroll_x(), @browser.scroll_y() + delta)
        }
      }
    }),
  })
}
