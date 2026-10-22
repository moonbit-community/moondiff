///|
pub(all) struct HistoryEntry {
  id : String
  sequence : Int32
  path : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) enum RouteDestination {
  Path(String)
  History(HistoryEntry)
} derive(Eq)

///|
pub(all) struct PagePosition {
  x : Double
  y : Double
  sidebar : Double
  focus_index : Int32?
  focus_label : String
} derive(Eq)

///|
pub(all) struct RouteMemory {
  review : @comments.NavigationReview
  snapshot : @comments.Snapshot?
  files : Array[(String, Bool, Array[String], Bool)]
  tree : FileTreeState
  range : (String, String, Bool)?
  mode : ViewMode
  algorithm : DiffAlgorithm
  ignore_comments : Bool
  ignore_tests : Bool
  draft_view : ChangeView?
} derive(Eq)

///|
pub(all) struct NavigationState {
  entry : HistoryEntry
  pending : RouteDestination?
  rollback : Bool
  restore_data : Bool
  restore_position : Bool
  restoration : HistoryRestoration?
  positions : Map[String, PagePosition]
  routes : Map[String, RouteMemory]
  pages : Array[ReadyPage]
} derive(Eq)

///|
// Only domain data is retained. Renderers, editors and requests own their own
// lifetimes and must never enter this cache.
pub(all) struct ReadyPage {
  user : String?
  version : String
  view : ChangeView
  range : RangeState?
} derive(Eq)

///|
pub fn NavigationState::new() -> NavigationState {
  {
    entry: { id: "initial", sequence: 0, path: "/", },
    pending: None,
    rollback: false,
    restore_data: false,
    restore_position: false,
    restoration: None,
    positions: {},
    routes: {},
    pages: [],
  }
}

///|
fn read_history_entry() -> HistoryEntry? {
  guard @browser.has_window() else { return None }
  try {
    let entry : HistoryEntry = @json.from_json(
      @json.parse(@browser.history_state()),
    )
    Some(entry)
  } catch {
    _ => None
  }
}

///|
fn initialize_navigation() -> NavigationState {
  let initial = NavigationState::new()
  guard @browser.has_window() else { return initial }
  let path = @url.parse(browser_current_url()).path catch { _ => "/" }
  let entry = read_history_entry().unwrap_or({
    id: @browser.history_entry_id(),
    sequence: 0,
    path,
  })
  @browser.manual_scroll_restoration()
  @browser.history_replace(
    ToJson::to_json(entry).stringify(),
    browser_current_url(),
  )
  { ..initial, entry, }
}

///|
fn navigation_blocked(model : Model) -> Bool {
  model.review.blocks_navigation() || model.pull_merge.submitting
}

///|
fn route_key(reference : CommitRef) -> String {
  @routing.review_route(reference)
}

///|
fn memory_snapshot(model : Model) -> @comments.Snapshot? {
  match model.phase {
    ShowingPullSelector(pull) =>
      model.route.map(reference => {
        reference,
        sha: pull.head.sha,
        pull_snapshot: Some(pull),
      })
    _ => comment_context(model).snapshot
  }
}

///|
fn route_version_key(
  reference : CommitRef,
  snapshot : @comments.Snapshot?,
) -> String {
  let version = match snapshot {
    Some({ sha, pull_snapshot: Some(pull), .. }) =>
      Json::array([
        Json(sha),
        ToJson::to_json(pull.base),
        ToJson::to_json(pull.head),
        Json(pull.changed_files),
        ToJson::to_json(pull.commits),
      ])
    Some({ sha, .. }) => Json(sha)
    None => Json::null()
  }
  "version:" + Json::array([Json(route_key(reference)), version]).stringify()
}

///|
fn save_route_memory(model : Model) -> Model {
  guard model.route is Some(reference) &&
    (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) else {
    return model
  }
  let routes = model.navigation.routes.copy()
  routes[route_key(reference)] = {
    review: model.review.export_navigation(),
    snapshot: memory_snapshot(model),
    files: match model.phase {
      Showing(view) =>
        view.files.map(file => {
          (
            file.file.filename,
            file.expanded,
            file.collapsed_sections.copy(),
            file.manually_collapsed,
          )
        })
      _ => []
    },
    tree: model.file_tree,
    range: model.range.map(state => {
      (state.from_sha, state.to_sha, state.expanded)
    }),
    mode: model.view_mode,
    algorithm: model.diff_algorithm,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
    // A draft must remain reviewable at its original version even if its parsed
    // page is too large or has been evicted. Retain only the immutable metadata.
    draft_view: match model.phase {
      Showing(view) if model.review.draft() is Some(_) =>
        Some(lightweight_page(view))
      _ => None
    },
  }
  routes[route_version_key(reference, memory_snapshot(model))] = routes[route_key(
      reference,
    )]
  let pages = match model.phase {
    Showing(view) if retain_page(view) => {
      let pages = model.navigation.pages.filter(page => {
        page.view.reference != reference
      })
      pages.push({
        user: model.last_authenticated_user_id,
        version: route_version_key(reference, memory_snapshot(model)),
        view,
        range: model.range,
      })
      // During navigation this may include the outgoing current page. The
      // destination is removed before limiting the two non-current pages.
      if pages.length() > 3 {
        pages[1:].to_owned()
      } else {
        pages
      }
    }
    _ => model.navigation.pages.filter(page => page.view.reference != reference)
  }
  { ..model, navigation: { ..model.navigation, routes, pages, }, }
}

///|
fn retain_page(view : ChangeView) -> Bool {
  let mut bytes = 0
  for file in view.files {
    for side in [file.old_side, file.new_side] {
      if side is Ready(lines) {
        bytes += Int32::max(0, lines.length() - 1)
        for line in lines {
          bytes += @utf8.encode(line).length()
          if bytes > 4 * 1048576 {
            return false
          }
        }
      }
    }
  }
  true
}

///|
fn ready_page(model : Model, reference : CommitRef) -> ReadyPage? {
  let ready = model.navigation.pages
    .iter()
    .find_first(page => {
      page.user == model.last_authenticated_user_id &&
      page.view.reference == reference &&
      model.navigation.routes
      .get(route_key(reference))
      .map(saved => page.version == route_version_key(reference, saved.snapshot))
      .unwrap_or(false)
    })
  if ready is Some(_) {
    ready
  } else {
    model.navigation.routes
    .get(route_key(reference))
    .bind(saved => {
      saved.draft_view.map(view => {
        user: model.last_authenticated_user_id,
        version: route_version_key(reference, saved.snapshot),
        view,
        range: None,
      })
    })
  }
}

///|
fn lightweight_page(view : ChangeView) -> ChangeView {
  {
    ..view,
    files: view.files.map(file => {
      let pair = source_pair_for_revisions(
        view.old_revision,
        view.new_revision,
        file.file,
      )
      {
        ..file,
        old_side: initial_side(pair.old_url, file.expanded),
        new_side: initial_side(pair.new_url, file.expanded),
        diff_cache: DiffCache::empty(),
      }
    }),
  }
}

///|
fn retained_pages(
  pages : Array[ReadyPage],
  current : CommitRef?,
) -> Array[ReadyPage] {
  let others = pages.filter(page => Some(page.view.reference) != current)
  if others.length() > 2 {
    others[others.length() - 2:].to_owned()
  } else {
    others
  }
}

///|
let focus_candidates : String = "a,button,input,textarea,select,[tabindex]"

///|
fn focus_label(element : @dom.Element) -> String {
  let path = element
    .closest("[data-file-path]")
    .bind(parent => parent.get_attribute("data-file-path"))
    .unwrap_or("")
  let tag : String = @browser.property(element, "tagName")
  for key in ["id", "href", "aria-label"] {
    if element.get_attribute(key) is Some(value) && !value.is_empty() {
      return "\{path}:\{tag}:\{value}"
    }
  }
  let text : String = @browser.property(element, "textContent")
  "\{path}:\{tag}:\{text}"
}

///|
fn save_navigation_page(model : Model) -> Model {
  let model = save_route_memory(model)
  guard @browser.has_window() else { return model }
  let focused = @dom.document().get_active_element()
  let candidates = @dom.document()
    .query_selector_all(focus_candidates)
    .iter()
    .collect()
  let focus_index = focused.bind(active => {
    candidates.search_by(element => @browser.same(active, element))
  })
  let positions = model.navigation.positions.copy()
  positions[model.navigation.entry.id] = {
    x: @browser.scroll_x(),
    y: @browser.scroll_y(),
    sidebar: @dom.document()
    .query_selector(".file-tree-scroll")
    .to_option()
    .map(el => el.get_scroll_top())
    .unwrap_or(0),
    focus_index,
    focus_label: focused.map(focus_label).unwrap_or(""),
  }
  { ..model, navigation: { ..model.navigation, positions, }, }
}

///|
fn route_notification(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  emit(Ui(RouteChanged(@url.parse(browser_current_url())))) catch {
    _ => @rabbita.none
  }
}

///|
fn history_command(
  entry : HistoryEntry,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    if @browser.has_window() {
      @browser.history_push(ToJson::to_json(entry).stringify(), entry.path)
      scheduler.add(route_notification(emit))
    }
  })
}

///|
fn history_go(delta : Int32) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => if @browser.has_window() { @browser.history_go(delta) })
}

///|
fn replace_route(path : String, emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    if @browser.has_window() {
      @browser.history_replace(@browser.history_state(), path)
      scheduler.add(route_notification(emit))
    }
  })
}

///|
fn request_navigation(
  model : Model,
  target : RouteDestination,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if navigation_blocked(model) || model.navigation.rollback {
    return (
      { ..model, navigation: { ..model.navigation, pending: Some(target), }, },
      @rabbita.none,
    )
  }
  match target {
    History(entry) =>
      (model, history_go(entry.sequence - model.navigation.entry.sequence))
    Path(path) => {
      let parsed = reference_from_review_url("http://localhost\{path}")
      guard parsed is Ok(_) else { return (model, @rabbita.none) }
      if path == model.navigation.entry.path {
        return (model, @rabbita.none)
      }
      let entry = {
        id: if @browser.has_window() {
          @browser.history_entry_id()
        } else {
          path
        },
        sequence: model.navigation.entry.sequence + 1,
        path,
      }
      // RouteChanged owns loading, including promotion of a shared task.
      @metrics.begin("click_to_diff")
      (model, history_command(entry, emit))
    }
  }
}

///|
fn navigation_write_failed(before : Model, next : Model) -> Bool {
  let posted = before.review
    .submission()
    .map(stage => !(stage is SyncingReview(_)))
    .unwrap_or(false) &&
    !next.review
    .submission()
    .map(stage => !(stage is SyncingReview(_)))
    .unwrap_or(false)
  let deleted = before.review.deletion is Some(Deleting(_)) &&
    !(next.review.deletion is Some(Deleting(_)))
  let merged = before.pull_merge.submitting && !next.pull_merge.submitting
  (
    posted &&
    (
      next.review
      .draft()
      .map(draft => !draft.submitting && draft.error is Some(_))
      .unwrap_or(false) ||
      next.auth is AuthFailed(_)
    )
  ) ||
  (deleted && next.review.deletion is Some(DeleteFailed(_, _))) ||
  (
    merged &&
    (
      next.pull_merge.error is Some(_) ||
      (
        next.pull_merge.stale &&
        !next.pull_merge.status.map(status => status.merged).unwrap_or(false)
      )
    )
  )
}

///|
fn reconcile_navigation(
  before : Model,
  next : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let failed = navigation_write_failed(before, next)
  let next = if failed {
    { ..next, navigation: { ..next.navigation, pending: None, }, }
  } else {
    next
  }
  if !navigation_blocked(next) &&
    !next.navigation.rollback &&
    next.navigation.pending is Some(target) {
    request_navigation(
      { ..next, navigation: { ..next.navigation, pending: None, }, },
      target,
      emit,
    )
  } else {
    (next, @rabbita.none)
  }
}

///|
fn restore_route_memory(model : Model) -> (Model, Array[String]) {
  guard model.navigation.restore_data &&
    model.route is Some(reference) &&
    (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) else {
    return (model, [])
  }
  let next = {
    ..model,
    navigation: { ..model.navigation, restore_data: false, },
  }
  let next = match
    (next.phase, next.navigation.routes.get(route_key(reference))) {
    (Showing(view), Some(saved)) => {
      let review = @comments.update(
          next.review,
          RestoreNavigation(
            saved.review,
            view.files.map(file => file.file.filename),
          ),
        ).0
      with_review(next, review)
    }
    _ => next
  }
  restore_route_preferences(next)
}

///|
fn restore_route_preferences(model : Model) -> (Model, Array[String]) {
  guard model.route is Some(reference) &&
    model.navigation.routes.get(
      route_version_key(reference, memory_snapshot(model)),
    )
    is Some(saved) else {
    return (model, [])
  }
  let restored : Array[String] = []
  let phase = match model.phase {
    Showing(view) => {
      let files = view.files.map(file => {
        match
          saved.files.iter().find_first(item => item.0 == file.file.filename) {
          Some((path, expanded, collapsed, manually_collapsed)) => {
            restored.push(path)
            {
              ..file,
              expanded,
              collapsed_sections: collapsed,
              manually_collapsed,
            }
          }
          None => file
        }
      })
      Showing(
        ensure_expanded_file_documents(
          { ..view, files, },
          saved.algorithm,
          ignore_comments=saved.ignore_comments,
          ignore_tests=saved.ignore_tests,
        ),
      )
    }
    other => other
  }
  let range = match (model.range, saved.range) {
    (Some(state), Some((from, to, expanded))) =>
      Some({ ..state, from_sha: from, to_sha: to, expanded, })
    _ => model.range
  }
  (
    {
      ..model,
      phase,
      range,
      file_tree: { ..saved.tree, drawer_open: false, },
      view_mode: saved.mode,
      diff_algorithm: saved.algorithm,
      ignore_comments: saved.ignore_comments,
      ignore_tests: saved.ignore_tests,
    },
    restored,
  )
}

///|
fn page_layout_ready(model : Model) -> Bool {
  match model.phase {
    Showing(view) =>
      (
        !(view.reference.target is PullRequest(_)) ||
        (
          !(model.access.freshness is Checking) &&
          !model.access.identity_checking
        )
      ) &&
      !model.range
      .map(state => state.expanded && state.loading_page is Some(_))
      .unwrap_or(false) &&
      !view.files.any(file => {
        file.expanded && (file.old_side is Loading || file.new_side is Loading)
      })
    Idle => model.auth != AuthChecking
    ShowingPullSelector(_) | LoadFailed(_) => true
    _ => false
  }
}

///|
fn restore_history_position(
  model : Model,
  restoration : HistoryRestoration,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let generation = model.generation
  let position = model.navigation.positions.get(model.navigation.entry.id)
  @cmd.custom_cmd(scheduler => {
    guard !restoration.cancelled else { return }
    if @browser.has_window() {
      if position is Some(position) {
        let candidates = @dom.document()
          .query_selector_all(focus_candidates)
          .iter()
          .collect()
        let indexed = position.focus_index.bind(index => candidates.get(index))
        let target = match indexed {
          Some(target) if focus_label(target) == position.focus_label =>
            Some(target)
          _ if !position.focus_label.is_empty() =>
            candidates
            .iter()
            .find_first(target => focus_label(target) == position.focus_label)
          _ => None
        }
        let found = match target {
          Some(target) => {
            guard !restoration.cancelled else { return }
            @browser.focus(target)
            true
          }
          _ => position.focus_index is None
        }
        if @dom.document().query_selector(".file-tree-scroll").to_option()
          is Some(sidebar) {
          guard !restoration.cancelled else { return }
          sidebar.set_scroll_top(position.sidebar)
        }
        guard !restoration.cancelled else { return }
        @browser.scroll_to(
          if found {
            position.x
          } else {
            0
          },
          if found {
            position.y
          } else {
            0
          },
        )
      } else if !restoration.cancelled {
        @browser.scroll_to(0, 0)
      }
    }
    @metrics.finish("back_restore")
    scheduler.add(emit(Ui(PositionRestored(generation, restoration.entry))))
  })
}

///|
fn restore_expanded_sources(
  before : Model,
  restored : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard before.navigation.restore_data &&
    !restored.navigation.restore_data &&
    restored.phase is Showing(view) else {
    return (restored, @rabbita.none)
  }
  let mut next = restored
  let commands = []
  for index, file in view.files {
    if file.expanded &&
      (file.old_side is NotRequested || file.new_side is NotRequested) &&
      next.phase is Showing(current) {
      let (expanded, command) = expand_file(
        next,
        current,
        next.generation,
        index,
        file,
        emit,
      )
      next = expanded
      commands.push(command)
    }
  }
  (next, @rabbita.batch(commands))
}
