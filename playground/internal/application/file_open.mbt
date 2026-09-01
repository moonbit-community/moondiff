///|
fn expand_file(
  model : Model,
  view : ChangeView,
  generation : Int,
  index : Int,
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
    file: file.file,
    diff_mode: file.diff_mode,
    expanded: true,
    old_side: if file.old_side is NotRequested {
      initial_side(pair.old_url, true)
    } else {
      file.old_side
    },
    new_side: if file.new_side is NotRequested {
      initial_side(pair.new_url, true)
    } else {
      file.new_side
    },
    diff_cache: file.diff_cache,
  }
  let command = if first_load {
    @rabbita.batch(commands_for_file(view, generation, index, emit))
  } else {
    @rabbita.none
  }
  (
    with_phase(
      model,
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
fn select_file(model : Model, index : Int) -> Model {
  {
    ..model,
    file_tree: {
      ..model.file_tree,
      drawer_open: false,
      selected_file_index: Some(index),
    },
  }
}
