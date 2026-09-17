///|
pub(all) enum Msg {
  Home(HomeMsg)
  Viewed(ViewedMsg)
  Auth(AuthMsg)
  Review(ReviewMsg)
  Load(LoadMsg)
  Ui(UiMsg)
}

///|
pub fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> Transition {
  let (next, command) = match msg {
    Home(msg) => update_home(model, msg, emit)
    Viewed(msg) => update_viewed(model, msg, emit)
    Auth(msg) => update_auth(model, msg, emit)
    Review(msg) => update_review(model, msg, emit)
    Load(msg) => update_load(model, msg, emit)
    Ui(msg) => update_ui(model, msg, emit)
  }
  let (next, viewed_command) = reconcile_viewed(model, next, msg, emit)
  let (next, home_command) = reconcile_home(model, next, msg, emit)
  {
    model: next,
    command: @rabbita.batch([command, viewed_command, home_command]),
    after_commit: ui_after_commit(model, next, msg, emit),
  }
}
