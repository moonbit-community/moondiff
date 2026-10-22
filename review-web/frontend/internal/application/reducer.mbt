///|
pub(all) enum Msg {
  Home(HomeMsg)
  Viewed(ViewedMsg)
  PullMerge(PullMergeMsg)
  Auth(AuthMsg)
  Review(ReviewMsg)
  Load(LoadMsg)
  Range(RangeMsg)
  Ui(UiMsg)
}

///|
pub fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> Transition {
  let model = prepare_reading_recovery(model, msg)
  let model = cancel_history_for_edit(model, msg)
  let model = synchronize_snapshot_permission(model)
  let (next, command) = match msg {
    Home(msg) => update_home(model, msg, emit)
    Viewed(msg) => update_viewed(model, msg, emit)
    PullMerge(msg) => update_pull_merge(model, msg, emit)
    Auth(msg) => update_auth(model, msg, emit)
    Review(msg) => update_review(model, msg, emit)
    Load(msg) => update_load(model, msg, emit)
    Range(msg) => update_range(model, msg, emit)
    Ui(msg) => update_ui(model, msg, emit)
  }
  let next = if msg is Auth(Logout) {
    {
      ..next,
      recovering_session: false,
      last_authenticated_user_id: None,
      review: @comments.update(next.review, Reset(true, false)).0,
      navigation: {
        ..next.navigation,
        routes: {},
        pages: [],
        positions: {},
        pending: None,
      },
    }
  } else {
    next
  }
  let (restored, restored_files) = restore_route_memory(next)
  let (next, restore_command) = restore_expanded_sources(next, restored, emit)
  let (next, navigation_command) = reconcile_navigation(model, next, emit)
  let (next, viewed_command) = reconcile_viewed(model, next, msg, emit)
  // Scope initialization must finish before restored layout counts as an edit.
  let mut next = next
  for path in restored_files {
    if next.phase is Showing(view) &&
      view.files.search_by(file => file.file.filename == path) is Some(index) {
      next = record_viewed_interaction(next, index)
    }
  }
  let (next, home_command) = reconcile_home(model, next, msg, emit)
  let (next, pull_merge_command) = reconcile_pull_merge(model, next, msg, emit)
  let next = reconcile_sign_in_dialog(model, next)
  let (next, snapshot_command) = resume_waiting_snapshot(next, emit)
  let next = synchronize_snapshot_permission(next)
  let next = pause_waiting_sources(next)
  let (next, sources_command) = reconcile_pull_sources(next, emit)
  let next = synchronize_history_restoration(model, next)
  let next = reconcile_reading_recovery(model, next, msg)
  {
    model: next,
    command: @rabbita.batch([
      command,
      restore_command,
      viewed_command,
      home_command,
      pull_merge_command,
      navigation_command,
      sources_command,
      snapshot_command,
      leave_home_prefetch(model, next),
    ]),
    after_commit: ui_after_commit(model, next, msg, emit),
    reading_recovery: next.reading_recovery,
  }
}
