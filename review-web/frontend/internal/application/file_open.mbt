///|
fn expand_file(
  model : Model,
  view : ChangeView,
  generation : Int32,
  index : Int32,
  file : @change.FileState,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let pair = source_pair_for_revisions(
    view.old_revision,
    view.new_revision,
    file.file,
  )
  let first_load = file.old_side is NotRequested ||
    file.new_side is NotRequested
  let changed = @change.FileState::{
    ..file,
    expanded: true,
    manually_collapsed: false,
    old_side: if file.old_side is NotRequested {
      if model.source_pause is Some(_) {
        Paused
      } else {
        initial_side(pair.old_url, true)
      }
    } else {
      file.old_side
    },
    new_side: if file.new_side is NotRequested {
      if model.source_pause is Some(_) {
        Paused
      } else {
        initial_side(pair.new_url, true)
      }
    } else {
      file.new_side
    },
  }
  let command = if model.source_pause is Some(_) ||
    view.reference.target is PullRequest(_) {
    @rabbita.none
  } else if first_load {
    @rabbita.batch(commands_for_file(view, generation, index, emit))
  } else {
    @rabbita.none
  }
  (
    with_phase(
      promote_pull_file(model, index),
      Showing(
        set_file_state(
          view,
          index,
          ensure_file_document(
            changed,
            model.diff_algorithm,
            ignore_comments=model.ignore_comments,
            ignore_tests=model.ignore_tests,
          ),
        ),
      ),
    ),
    command,
  )
}

///|
fn select_file(model : Model, index : Int32) -> Model {
  {
    ..model,
    navigation: { ..model.navigation, restore_position: false, },
    file_tree: {
      ..model.file_tree,
      drawer_open: false,
      selected_file_index: Some(index),
    },
  }
}
