///|
pub(all) enum Msg {
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
    Auth(msg) => update_auth(model, msg, emit)
    Review(msg) => update_review(model, msg, emit)
    Load(msg) => update_load(model, msg, emit)
    Ui(msg) => update_ui(model, msg, emit)
  }
  (next, @rabbita.batch([command, editor_after_update(next)]))
}
