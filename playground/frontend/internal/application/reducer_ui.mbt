///|
pub(all) enum UiMsg {
  InputChanged(String)
  Submit
  RouteChanged(@url.Url)
  SelectView(ViewMode)
  ToggleFileTreeDrawer
  CloseFileTreeDrawer
  FileTreeViewportChanged(Int)
  FileTreeWidthChanged(Int)
  ToggleFileTreeSearch
  FileTreeSearchChanged(String)
  ToggleFileTreeStatus(String)
  ToggleFileTreeDirectory(String)
  SelectDiffAlgorithm(DiffAlgorithm)
  ToggleIgnoreComments
  ToggleIgnoreTests
}

///|
fn update_ui(
  model : Model,
  msg : UiMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  // Navigation may arrive while the initial session request is still pending.
  // Keep generation zero so its response starts only the latest selected route.
  if model.generation == 0 &&
    model.auth is AuthChecking &&
    msg is RouteChanged(url) {
    return match reference_from_playground_url(url.to_string()) {
      Ok(Some(reference)) =>
        (
          {
            ..model,
            route: Some(reference),
            restore_pending: false,
            input: canonical_github_url(reference),
            phase: Idle,
          },
          @rabbita.none,
        )
      Ok(None) =>
        (
          {
            ..model,
            route: None,
            restore_pending: false,
            input: "",
            phase: Idle,
          },
          @rabbita.none,
        )
      Err(message) =>
        (
          {
            ..model,
            route: None,
            restore_pending: false,
            input: "",
            phase: LoadFailed(message),
          },
          @rabbita.none,
        )
    }
  }
  let (next, command) = match msg {
    InputChanged(value) => ({ ..model, input: value, }, @rabbita.none)
    SelectView(view_mode) => ({ ..model, view_mode, }, @rabbita.none)
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
    FileTreeWidthChanged(width) =>
      (
        {
          ..model,
          file_tree: {
            ..model.file_tree,
            preferred_width: normalize_file_tree_width(width),
          },
        },
        @rabbita.none,
      )
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
              restore_pending: false,
              phase: LoadFailed(message),
              file_tree: reset_file_tree_state(model.file_tree),
            },
            @rabbita.none,
          )
        Ok(reference) => {
          if model.generation == 0 && model.auth is AuthChecking {
            return (
              {
                ..model,
                route: Some(reference),
                restore_pending: false,
                input: canonical_github_url(reference),
              },
              @nav.push_url(playground_share_url(reference)),
            )
          }
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
      match reference_from_playground_url(url.to_string()) {
        Err(message) =>
          (
            {
              ..model,
              input: "",
              generation: model.generation + 1,
              restore_pending: false,
              phase: LoadFailed(message),
              route: None,
              file_tree: reset_file_tree_state(model.file_tree),
            },
            @github_client.cancel_before(model.generation + 1),
          )
        Ok(None) =>
          (
            {
              ..model,
              input: "",
              generation: model.generation + 1,
              restore_pending: false,
              phase: Idle,
              route: None,
              file_tree: reset_file_tree_state(model.file_tree),
            },
            @github_client.cancel_before(model.generation + 1),
          )
        Ok(Some(reference)) =>
          if model.route == Some(reference) {
            (model, @rabbita.none)
          } else {
            begin_change_load(model, reference, emit)
          }
      }
  }
  if model.restore_pending && !next.restore_pending && next.auth is AuthChecking {
    // Navigation invalidates the scoped restoration query. Resolve the session
    // again so the new route cannot remain stuck in AuthChecking.
    (
      next,
      @rabbita.batch([command, auth_status_request(next.auth_revision, emit)]),
    )
  } else {
    (next, command)
  }
}
