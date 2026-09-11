///|
pub(all) enum Msg {
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
) -> (Model, @rabbita.Cmd) {
  capture_editor()
  let (next, command) = match msg {
    Viewed(msg) => update_viewed(model, msg, emit)
    Auth(msg) => update_auth(model, msg, emit)
    Review(msg) => update_review(model, msg, emit)
    Load(msg) => update_load(model, msg, emit)
    Ui(msg) => update_ui(model, msg, emit)
  }
  let (next, viewed_command) = reconcile_viewed(model, next, msg, emit)
  (next, @rabbita.batch([command, viewed_command, editor_after_update(next)]))
}
