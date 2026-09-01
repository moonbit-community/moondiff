///|
pub(all) enum UiMsg {
  InputChanged(String)
  Submit
  RouteChanged(@url.Url)
  ToggleView
  ToggleFileTreeDrawer
  CloseFileTreeDrawer
  FileTreeViewportChanged(Int)
  ToggleFileTreeSearch
  FileTreeSearchChanged(String)
  ToggleFileTreeStatus(String)
  ToggleFileTreeDirectory(String)
  SelectDiffAlgorithm(DiffAlgorithm)
  ToggleIgnoreComments
  ToggleIgnoreTests
  CopyShareLink
  ShareCopied
  ShareCopyFailed(String)
}

///|
fn update_ui(
  model : Model,
  msg : UiMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    InputChanged(value) =>
      ({ ..model, input: value, copy_status: CopyReady, }, @rabbita.none)
    ToggleView => {
      let view_mode = if model.view_mode is Split {
        @change.Unified
      } else {
        Split
      }
      ({ ..model, view_mode, }, @rabbita.none)
    }
    ToggleFileTreeDrawer => {
      let drawer_open = !model.file_tree.drawer_open
      let focus_command = if drawer_open {
        focus_selector_after_render("#file-tree-sidebar .drawer-close")
      } else {
        focus_selector_after_render(".file-tree-trigger")
      }
      (
        { ..model, file_tree: { ..model.file_tree, drawer_open, }, },
        focus_command,
      )
    }
    CloseFileTreeDrawer => {
      let focus_command = if model.file_tree.drawer_open {
        focus_selector_after_render(".file-tree-trigger")
      } else {
        @rabbita.none
      }
      (
        { ..model, file_tree: { ..model.file_tree, drawer_open: false, }, },
        focus_command,
      )
    }
    FileTreeViewportChanged(width) =>
      if model.file_tree.drawer_open && width >= 768 {
        (
          { ..model, file_tree: { ..model.file_tree, drawer_open: false, }, },
          focus_selector_after_render("#file-tree-sidebar .search-toggle"),
        )
      } else {
        (model, @rabbita.none)
      }
    ToggleFileTreeSearch => {
      let search_open = !model.file_tree.search_open
      (
        {
          ..model,
          file_tree: {
            ..model.file_tree,
            search_open,
            search_query: if search_open {
              model.file_tree.search_query
            } else {
              ""
            },
          },
        },
        @rabbita.none,
      )
    }
    FileTreeSearchChanged(query) =>
      (
        { ..model, file_tree: { ..model.file_tree, search_query: query, }, },
        @rabbita.none,
      )
    ToggleFileTreeStatus(status) =>
      (
        {
          ..model,
          file_tree: {
            ..model.file_tree,
            selected_statuses: toggle_file_tree_value(
              model.file_tree.selected_statuses,
              status,
            ),
          },
        },
        @rabbita.none,
      )
    ToggleFileTreeDirectory(path) =>
      (
        {
          ..model,
          file_tree: {
            ..model.file_tree,
            collapsed_directories: toggle_file_tree_value(
              model.file_tree.collapsed_directories,
              path,
            ),
          },
        },
        @rabbita.none,
      )
    SelectDiffAlgorithm(algorithm) => {
      if algorithm == model.diff_algorithm {
        return (model, @rabbita.none)
      }
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests=model.ignore_tests,
            ),
          )
        other => other
      }
      ({ ..model, diff_algorithm: algorithm, phase, }, @rabbita.none)
    }
    ToggleIgnoreComments => {
      let ignore_comments = !model.ignore_comments
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              model.diff_algorithm,
              ignore_comments~,
              ignore_tests=model.ignore_tests,
            ),
          )
        other => other
      }
      ({ ..model, ignore_comments, phase, }, @rabbita.none)
    }
    ToggleIgnoreTests => {
      let ignore_tests = !model.ignore_tests
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              model.diff_algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests~,
            ),
          )
        other => other
      }
      ({ ..model, ignore_tests, phase, }, @rabbita.none)
    }
    Submit =>
      match parse_change_url(model.input) {
        Err(message) =>
          (
            {
              ..model,
              generation: model.generation + 1,
              phase: LoadFailed(message),
              copy_status: CopyReady,
              file_tree: initial_file_tree_state(),
            },
            @rabbita.none,
          )
        Ok(reference) => {
          let already_at_route = model.route == Some(reference)
          let (next, request) = begin_change_load(model, reference, emit)
          let navigation = if already_at_route {
            @rabbita.none
          } else {
            @nav.push_url(playground_share_url(reference))
          }
          (next, @rabbita.batch([navigation, request]))
        }
      }
    RouteChanged(url) =>
      match reference_from_route(url.fragment) {
        Err(message) =>
          (
            {
              ..model,
              input: "",
              generation: model.generation + 1,
              phase: LoadFailed(message),
              route: None,
              share_url: None,
              copy_status: CopyReady,
              file_tree: initial_file_tree_state(),
            },
            @rabbita.none,
          )
        Ok(None) =>
          (
            {
              ..model,
              input: "",
              generation: model.generation + 1,
              phase: Idle,
              route: None,
              share_url: None,
              copy_status: CopyReady,
              file_tree: initial_file_tree_state(),
            },
            @rabbita.none,
          )
        Ok(Some(reference)) =>
          if model.route == Some(reference) {
            (model, @rabbita.none)
          } else {
            begin_change_load(model, reference, emit)
          }
      }
    CopyShareLink =>
      if model.share_url is Some(url) {
        (
          model,
          @clipboard.copy(Text(url), copied=emit(Ui(ShareCopied)), failed=message => {
            emit(Ui(ShareCopyFailed(message)))
          }),
        )
      } else {
        (model, @rabbita.none)
      }
    ShareCopied => ({ ..model, copy_status: Copied, }, @rabbita.none)
    ShareCopyFailed(message) =>
      ({ ..model, copy_status: CopyError(message), }, @rabbita.none)
  }
}
