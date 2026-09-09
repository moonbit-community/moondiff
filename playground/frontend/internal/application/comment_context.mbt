///|
fn comment_context(model : Model) -> @comments.Context {
  {
    generation: model.generation,
    route: model.route,
    enabled: true,
    snapshot: match model.phase {
      Showing(view) =>
        Some({
          reference: view.reference,
          sha: view.sha,
          pull_snapshot: view.pull_snapshot,
        })
      _ => None
    },
  }
}

///|
fn comment_session_context(
  session : Session,
  context : @comments.Context,
) -> Session {
  @comments.update(session, ContextChanged(context)).0
}
