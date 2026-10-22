///|
// The current PR owns validated SideLoad values, independently of the shared
// transport cache. Only four sides are admitted at a time, including all
// expanded interface files. Historical page retention keeps its existing budget.
pub(all) struct PullSourceState {
  generation : Int32
  pending : Array[(Int32, SourceSide)]
  urgent : Array[Int32]
  cursor : Int32
} derive(Eq)

///|
#deprecated
#doc(hidden)
pub extend PullSourceState with Eq::{not_equal, equal}

///|
fn PullSourceState::new(generation : Int32) -> PullSourceState {
  { generation, pending: [], urgent: [], cursor: 0, }
}

///|
fn prefetch_file(file : @change.FileState) -> Bool {
  @github.is_moonbit_file(file.file.filename) ||
  file.file.previous_filename.map(@github.is_moonbit_file).unwrap_or(false)
}

///|
fn promote_pull_file(model : Model, index : Int32) -> Model {
  guard model.pull_sources is Some(state) &&
    state.generation == model.generation else {
    return model
  }
  let urgent = [index]
  for previous in state.urgent {
    if previous != index {
      urgent.push(previous)
    }
  }
  { ..model, pull_sources: Some({ ..state, urgent, }), }
}

///|
fn file_side(file : @change.FileState, side : SourceSide) -> SideLoad {
  match side {
    Old => file.old_side
    New => file.new_side
  }
}

///|
fn pull_source_identity_ready(model : Model) -> Bool {
  !model.access.identity_checking &&
  (
    model.auth is (SignedIn(..) | Anonymous(_)) ||
    (model.auth is AuthFailed(_) && model.last_authenticated_user_id is None)
  )
}

///|
fn reconcile_pull_sources(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(_) &&
    model.pull_sources is Some(state) &&
    state.generation == model.generation else {
    return (
      if model.pull_sources is Some(_) {
        { ..model, pull_sources: None, }
      } else {
        model
      },
      @rabbita.none,
    )
  }
  let pending = state.pending.filter(entry => {
    let (index, side) = entry
    view.files
    .get(index)
    .map(file => file_side(file, side) is (Loading | Paused))
    .unwrap_or(false)
  })
  let urgent = state.urgent.filter(index => {
    view.files
    .get(index)
    .map(file => {
      file.old_side is (Loading | NotRequested | Paused) ||
      file.new_side is (Loading | NotRequested | Paused)
    })
    .unwrap_or(false)
  })
  let automatic = model.page_visible &&
    (!@browser.has_window() || !@dom.document().hidden())
  let commands = []
  let mut current = view
  let mut cursor = state.cursor
  fn admit(index : Int32) -> Unit {
    for (side, location) in source_requests_for_file(current, index) {
      if pending.length() >= 4 {
        break
      }
      let file = current.files[index]
      if pending.contains((index, side)) ||
        !(file_side(file, side) is (NotRequested | Loading)) {
        continue
      }
      pending.push((index, side))
      if file_side(file, side) is NotRequested {
        let changed = match side {
          Old => { ..file, old_side: Loading, }
          New => { ..file, new_side: Loading, }
        }
        current = set_file_state(current, index, changed)
      }
      commands.push(
        source_load_request(
          location,
          model.generation,
          index,
          side,
          emit,
          priority=urgent.contains(index) || file.expanded,
        ),
      )
    }
  }
  if pull_source_identity_ready(model) && model.source_pause is None {
    for index in urgent {
      if pending.length() >= 4 {
        break
      }
      admit(index)
    }
    if automatic && pending.length() < 4 {
      // Initial expansions precede the sequential background cursor. This scans
      // metadata only, and never constructs a request queue for the entire PR.
      for index, file in current.files {
        if pending.length() >= 4 {
          break
        }
        if file.expanded && prefetch_file(file) {
          admit(index)
        }
      }
      while model.auth is SignedIn(..) &&
            cursor < current.files.length() &&
            pending.length() < 4 {
        if prefetch_file(current.files[cursor]) {
          admit(cursor)
        }
        let file = current.files[cursor]
        let remaining = [(SourceSide::Old, file.old_side), (New, file.new_side)].any(entry => {
            entry.1 is (Loading | NotRequested) &&
            !pending.contains((cursor, entry.0))
          },
        )
        if prefetch_file(file) && remaining {
          break
        }
        cursor += 1
      }
    }
  }
  let updated = { ..state, pending, urgent, cursor, }
  @metrics.state("pull_sources", "pending", pending.length())
  let next = if updated == state && @identity.same(current, view) {
    model
  } else {
    with_phase({ ..model, pull_sources: Some(updated), }, Showing(current))
  }
  (next, @rabbita.batch(commands))
}

///|
pub fn auto_expand_allowed(model : Model) -> Bool {
  model.phase is Showing(view) &&
  view.reference.target is PullRequest(_) &&
  model.page_visible &&
  model.source_pause is None &&
  pull_source_identity_ready(model) &&
  !model.navigation.restore_position &&
  !model.navigation.restore_data &&
  model.navigation.pending is None &&
  !model.restore_pending &&
  model.review.draft() is None
}

///|
pub fn auto_expand_candidate(model : Model, index : Int32) -> Bool {
  guard model.phase is Showing(view) &&
    view.reference.target is PullRequest(_) &&
    view.files.get(index) is Some(file) else {
    return false
  }
  !file.expanded &&
  !file.manually_collapsed &&
  prefetch_file(file) &&
  !model.viewed.files
  .get(index)
  .map(file => file.state is Some(Viewed))
  .unwrap_or(false)
}
