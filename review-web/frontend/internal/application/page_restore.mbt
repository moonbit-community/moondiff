///|
// Resume interrupted reads after page restoration or reauthorization. Ordinary
// focus refreshes leave in-flight file requests alone, including collapsed files.
fn restore_page_requests(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = { ..model, restore_pending: false, }
  if next.source_pause is Some(_) {
    return (pause_waiting_sources(next), @rabbita.none)
  }
  guard next.route is Some(reference) else { return (next, @rabbita.none) }
  let (next, snapshot_command) = if reference.target is PullRequest(_) &&
    (next.phase is Showing(_) || next.phase is ShowingPullSelector(_)) &&
    (
      next.access.freshness is Checking ||
      next.access.freshness is Unavailable(_)
    ) {
    (
      { ..next, access: { ..next.access, freshness: Checking, }, },
      shared_snapshot_request(
        reference,
        next.generation,
        emit,
        recovery=next.reading_recovery,
      ),
    )
  } else {
    (next, @rabbita.none)
  }
  match next.phase {
    Showing(view) => {
      let commands = [
        snapshot_command,
        comments_request(
          reference,
          next.generation,
          emit,
          recovery=next.reading_recovery,
        ),
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
      if reference.target is PullRequest(_) {
        let sources = match next.pull_sources {
          Some(state) if state.generation == next.generation => {
            // Resume only admitted reads, including manually collapsed files
            // behind the cursor. Keeping their slots also preserves a stopped
            // snapshot's rate-limit policy and the four-side admission bound.
            for (index, side) in state.pending {
              for
                (requested_side, location) in source_requests_for_file(
                  view, index,
                ) {
                if side == requested_side &&
                  file_side(view.files[index], side) is Loading {
                  commands.push(
                    source_load_request(
                      location,
                      next.generation,
                      index,
                      side,
                      emit,
                    ),
                  )
                }
              }
            }
            state
          }
          _ => {
            let urgent = []
            for index, file in view.files {
              if file.old_side is Loading || file.new_side is Loading {
                urgent.push(index)
              }
            }
            { ..PullSourceState::new(next.generation), urgent, }
          }
        }
        return (
          { ..next, pull_sources: Some(sources), },
          @rabbita.batch(commands),
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
    LoadFailed(_) =>
      (
        next,
        comments_request(
          reference,
          next.generation,
          emit,
          recovery=next.reading_recovery,
        ),
      )
    _ => begin_change_load(next, reference, emit, preserve_draft=true)
  }
}
