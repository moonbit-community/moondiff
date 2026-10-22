///|
pub fn app_init(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  let model = {
    ..initial_model(),
    navigation: initialize_navigation(),
    page_visible: !@browser.has_window() || !@dom.document().hidden(),
  }
  let next = match reference_from_review_url(browser_current_url()) {
    Ok(Some(reference)) =>
      {
        ..model,
        route: Some(reference),
        input: canonical_github_url(reference),
      }
    Ok(None) => model
    Err(message) => with_phase(model, LoadFailed(message))
  }
  (next, auth_status_request(next.auth_revision, emit))
}

///|
pub fn app_subscriptions(model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let base = @sub.batch([
    @sub.on_url_changed(url => emit(Ui(RouteChanged(url)))),
    page_reactivation_subscription(emit),
    history_interaction_subscription(model, emit),
  ])
  if model.file_tree.drawer_open {
    @sub.batch([
      base,
      @sub.on_resize(viewport => {
        emit(Ui(FileTreeViewportChanged(viewport.width.to_int())))
      }),
    ])
  } else {
    base
  }
}
