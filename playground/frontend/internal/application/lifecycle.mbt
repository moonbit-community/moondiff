///|
pub fn app_init(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  let model = initial_model()
  let (next, command) = match
    reference_from_playground_url(browser_current_url()) {
    Ok(Some(reference)) => begin_change_load(model, reference, emit)
    Ok(None) => (model, @rabbita.none)
    Err(message) => (with_phase(model, LoadFailed(message)), @rabbita.none)
  }
  if extension_host_enabled() {
    (next, @rabbita.batch([auth_status_request(emit), command]))
  } else {
    (next, command)
  }
}

///|
pub fn app_subscriptions(model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let base = if extension_host_enabled() {
    @sub.batch([
      @sub.on_url_changed(url => emit(Ui(RouteChanged(url)))),
      page_reactivation_subscription(emit),
    ])
  } else {
    @sub.on_url_changed(url => emit(Ui(RouteChanged(url))))
  }
  if model.file_tree.drawer_open {
    @sub.batch([
      base,
      @sub.on_resize(viewport => {
        emit(Ui(FileTreeViewportChanged(viewport.width)))
      }),
    ])
  } else {
    base
  }
}
