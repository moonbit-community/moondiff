///|
// Only page restoration resumes aborted reads. Ordinary focus refreshes must
// leave in-flight file requests alone, including requests for collapsed files.
fn restore_page_requests(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = { ..model, restore_pending: false, }
  guard next.route is Some(reference) else { return (next, @rabbita.none) }
  match next.phase {
    Showing(view) => {
      let commands = [comments_request(reference, next.generation, emit)]
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
    LoadFailed(_) => (next, comments_request(reference, next.generation, emit))
    _ => begin_change_load(next, reference, emit, preserve_draft=true)
  }
}
