///|
// Resume interrupted reads after page restoration or reauthorization. Ordinary
// focus refreshes leave in-flight file requests alone, including collapsed files.
fn restore_page_requests(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = { ..model, restore_pending: false, }
  guard next.route is Some(reference) else { return (next, @rabbita.none) }
  let (next, snapshot_command) = if reference.target is PullRequest(_) &&
    (next.phase is Showing(_) || next.phase is ShowingPullSelector(_)) &&
    (
      next.access.freshness is Checking ||
      next.access.freshness is Unavailable(_)
    ) {
    (
      { ..next, access: { ..next.access, freshness: Checking, }, },
      shared_snapshot_request(reference, next.generation, emit),
    )
  } else {
    (next, @rabbita.none)
  }
  match next.phase {
    Showing(view) => {
      let commands = [
        snapshot_command,
        comments_request(reference, next.generation, emit),
      ]
      if next.range is Some(state) && state.loading_page is Some(page) {
        commands.push(
          range_commit_page_request(
            reference,
            state,
            page,
            next.generation,
            emit,
          ),
        )
      }
      for index, file in view.files {
        for request in source_requests_for_file(view, index) {
          let (side, location) = request
          let state = match side {
            Old => file.old_side
            New => file.new_side
          }
          if state is Loading {
            commands.push(
              source_load_request(location, next.generation, index, side, emit),
            )
          }
        }
      }
      (next, @rabbita.batch(commands))
    }
    ShowingPullSelector(_) => {
      let commands = [snapshot_command]
      if next.range is Some({ loading_page: Some(page), .. } as state) {
        commands.push(
          range_commit_page_request(
            reference,
            state,
            page,
            next.generation,
            emit,
          ),
        )
      }
      (next, @rabbita.batch(commands))
    }
    LoadFailed(_) => (next, comments_request(reference, next.generation, emit))
    _ => begin_change_load(next, reference, emit, preserve_draft=true)
  }
}
