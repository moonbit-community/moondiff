///|
pub fn file_navigation_enabled(model : Model, index : Int32) -> Bool {
  guard model.phase is Showing(view) &&
    view.files.get(index) is Some(file) &&
    file.expanded else {
    return false
  }
  if view.reference.target is PullRequest(_) &&
    model.viewed.files.get(index) is Some({ state: Some(Viewed), .. }) {
    return false
  }
  @change.has_navigable_changes(
    file,
    model.diff_algorithm,
    ignore_comments=model.ignore_comments,
    ignore_tests=model.ignore_tests,
  )
}

///|
pub fn navigate_section_change(
  event : @dom.MouseEvent,
  generation : Int32,
  direction : Int32,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  find_section_change(
    event,
    generation,
    direction,
    section_change_inset,
    (file_index, key, block) => {
      emit(Load(NavigateChange(generation, file_index, key, block, direction)))
    },
    @rabbita.none,
  )
}

///|
// The same measured stack determines selection and landing, even when the
// target section is still collapsed or has not reached its sticky position.
fn section_change_inset(section : @dom.Element) -> Double {
  let summary = section.query_selector(".semantic-section-title").unwrap()
  let heading = section
    .closest(".file-card")
    .unwrap()
    .query_selector(".file-heading")
    .unwrap()
  let toolbar = @dom.document()
    .query_selector(".hero-workspace")
    .to_option()
    .unwrap()
  let title = section
    .closest(".change-main")
    .unwrap()
    .query_selector(".change-titlebar")
    .unwrap()
  toolbar.get_bounding_client_rect().get_height() +
  title.get_bounding_client_rect().get_height() +
  heading.get_bounding_client_rect().get_height() +
  summary.get_bounding_client_rect().get_height() +
  8.0
}

///|
priv struct NavigationLanding {
  main : @dom.Element
  target : @dom.Element
  scroll_y : Double
  scroll_height : Double
  top : Double
}

///|
let navigation_landing : Ref[NavigationLanding?] = Ref(None)

///|
pub fn clear_navigation_landing(main : @dom.Element) -> Unit {
  if navigation_landing.val is Some(landing) &&
    @browser.same(landing.main, main) {
    navigation_landing.val = None
  }
}

///|
pub fn clear_navigation_landings() -> Unit {
  navigation_landing.val = None
}

///|
pub fn navigation_scrolled(main : @dom.Element) -> Unit {
  if navigation_landing.val is Some(landing) &&
    @browser.same(landing.main, main) &&
    (@dom.window().scroll_y() - landing.scroll_y).abs() > 1.0 {
    navigation_landing.val = None
  }
}

///|
priv struct NavigationTarget {
  file : @dom.Element
  section : @dom.Element
  row : @dom.Element
}

///|
fn navigation_generation(element : @dom.Element, generation : Int32) -> Bool {
  element.get_attribute("data-navigation-generation") ==
  Some(generation.to_string())
}

///|
// Flatten DOM order, including the trailing group of deleted declarations.
// Eligibility and geometry are re-read on every activation; hidden rows in a
// collapsed section are targets, but cannot supply a reading position.
fn find_section_change(
  event : @dom.MouseEvent,
  generation : Int32,
  direction : Int32,
  inset : (@dom.Element) -> Double,
  navigate : (Int32, String, Int32) -> @rabbita.Cmd,
  none : @rabbita.Cmd,
) -> @rabbita.Cmd {
  event.prevent_default()
  event.stop_propagation()
  guard @browser.current_element(event.current_target()) is Some(button) &&
    button.closest(".change-main") is Some(main) &&
    navigation_generation(main, generation) else {
    return none
  }
  let targets : Array[NavigationTarget] = []
  let mut current = -1
  let mut boundary = 0
  for
    file in main
    .query_selector_all(".file-card.expanded[data-navigation-enabled=\"true\"]")
    .iter() {
    if !navigation_generation(file, generation) {
      continue
    }
    for section in file.query_selector_all(".semantic-section").iter() {
      if !navigation_generation(section, generation) {
        continue
      }
      let rows = section
        .query_selector_all("[data-change-block-start]")
        .iter()
        .collect()
      let edge = inset(section) + 1.0
      let heading_edge = edge -
        section
        .query_selector("summary")
        .unwrap()
        .get_bounding_client_rect()
        .get_height() -
        8.0
      let rect = section.get_bounding_client_rect()
      let start = targets.length()
      for row in rows {
        targets.push({ file, section, row, })
      }
      if rect.get_bottom() <= heading_edge {
        boundary = targets.length()
      } else if rect.get_top() <= heading_edge {
        boundary = start
        if (@browser.property(section, "open") : Bool) {
          for i, row in rows {
            if row.get_bounding_client_rect().get_top() > edge {
              break
            }
            current = start + i
          }
        }
      }
    }
  }
  if targets.is_empty() {
    return none
  }
  let at_landing = match navigation_landing.val {
    Some(landing) if @browser.same(main, landing.main) =>
      match
        targets.search_by(target => @browser.same(target.row, landing.target)) {
        Some(index) if (@browser.property(targets[index].section, "open") : Bool) &&
          (@dom.window().scroll_y() - landing.scroll_y).abs() <= 1.0 &&
          @dom.document().get_document_element().unwrap().get_scroll_height() ==
          landing.scroll_height &&
          (landing.target.get_bounding_client_rect().get_top() - landing.top).abs() <=
          1.0 => {
          current = index
          true
        }
        _ => false
      }
    _ => false
  }
  if !at_landing && @dom.window().scroll_y() <= 1.0 {
    current = -1
    boundary = 0
  }
  let next = if current < 0 {
    boundary + (if direction > 0 { 0 } else { -1 })
  } else {
    current + direction
  }
  let target = targets[(next + targets.length()) % targets.length()]
  let file_index = @string.parse_int(
    target.file.get_attribute("data-file-index").unwrap(),
  ) catch {
    _ => return none
  }
  let block = @string.parse_int(
    target.row.get_attribute("data-change-block-start").unwrap(),
  ) catch {
    _ => return none
  }
  navigate(
    file_index,
    target.section.get_attribute("data-section-key").unwrap(),
    block,
  )
}

///|
fn navigate_change_after_commit(
  generation : Int32,
  file_index : Int32,
  section_key : String,
  block : Int32,
  direction : Int32,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    scroll_to_section_change(
      generation,
      file_dom_id(file_index),
      section_key,
      block,
      direction,
      section_change_inset,
    )
  })
}

///|
fn scroll_to_section_change(
  generation : Int32,
  file_id : String,
  section_key : String,
  block : Int32,
  direction : Int32,
  inset : (@dom.Element) -> Double,
) -> Unit {
  guard @browser.element(file_id) is Some(file) &&
    file.matches(".expanded[data-navigation-enabled=\"true\"]") &&
    navigation_generation(file, generation) &&
    file.closest(".change-main") is Some(main) &&
    navigation_generation(main, generation) else {
    return
  }
  let sections = file.query_selector_all(".semantic-section").iter().collect()
  guard sections.search_by(element => {
      element.get_attribute("data-section-key") == Some(section_key) &&
      navigation_generation(element, generation)
    })
    is Some(index) else {
    return
  }
  let section = sections[index]
  if !(@browser.property(section, "open") : Bool) {
    return
  }
  guard section.query_selector("[data-change-block-start=\"\{block}\"]")
    is Some(target) else {
    return
  }
  let top = @dom.window().scroll_y() +
    target.get_bounding_client_rect().get_top() -
    inset(section)
  let maximum = 0.0.max(
    @dom.document().get_document_element().unwrap().get_scroll_height() -
    @dom.window().inner_height(),
  )
  @dom.window().scroll_to(0.0, 0.0.max(top.min(maximum)), behavior="instant")
  navigation_landing.val = if top > maximum || top < 0.0 {
    Some({
      main,
      target,
      scroll_y: @dom.window().scroll_y(),
      scroll_height: @dom.document()
      .get_document_element()
      .unwrap()
      .get_scroll_height(),
      top: target.get_bounding_client_rect().get_top(),
    })
  } else {
    None
  }
  if main.query_selector(
      ".change-titlebar [data-change-direction=\"\{direction}\"]",
    )
    is Some(button) {
    @browser.focus(button)
  }
}
