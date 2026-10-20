///|
pub(all) enum UiMsg {
  Navigate(String)
  PositionRestored(Int32, String)
  InputChanged(String)
  Submit
  RetryRoute
  RouteChanged(@url.Url)
  SelectView(ViewMode)
  OpenSignIn(Int32, SignInEntry, @dom.Element?)
  CloseSignIn(Int32, Int32)
  ToggleFileTreeDrawer
  CloseFileTreeDrawer
  FileTreeViewportChanged(Int32)
  FileTreeWidthChanged(Int32)
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
  if msg is Navigate(path) {
    return request_navigation(model, Path(path), emit)
  }
  if msg is PositionRestored(generation, entry) {
    return (
      if generation == model.generation && entry == model.navigation.entry.id {
        {
          ..model,
          navigation: { ..model.navigation, restore_position: false, },
        }
      } else {
        model
      },
      @rabbita.none,
    )
  }
  let model = if msg is RouteChanged(_) {
    let entry = read_history_entry().unwrap_or(model.navigation.entry)
    if model.navigation.rollback {
      return (
        {
          ..model,
          navigation: {
            ..model.navigation,
            rollback: entry.id != model.navigation.entry.id,
          },
        },
        @rabbita.none,
      )
    }
    if entry.id != model.navigation.entry.id {
      if navigation_blocked(model) {
        return (
          {
            ..model,
            navigation: {
              ..model.navigation,
              pending: Some(History(entry)),
              rollback: true,
            },
          },
          history_go(model.navigation.entry.sequence - entry.sequence),
        )
      }
      if model.navigation.positions.contains(entry.id) {
        @metrics.begin("back_restore")
      }
      let saved = save_navigation_page(model)
      {
        ..saved,
        navigation: {
          ..saved.navigation,
          entry,
          restore_position: true,
          restore_data: true,
        },
      }
    } else {
      model
    }
  } else {
    model
  }
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
    Navigate(_) | PositionRestored(_, _) => (model, @rabbita.none)
    InputChanged(value) => ({ ..model, input: value, }, @rabbita.none)
    SelectView(view_mode) => ({ ..model, view_mode, }, @rabbita.none)
    OpenSignIn(generation, entry, _) => {
      guard generation == model.generation &&
        !(model.auth is SignedIn(..)) &&
        model.phase is Showing(view) &&
        view.reference.target is PullRequest(_) &&
        view.files.get(entry.file_index()) is Some(_) else {
        return (model, @rabbita.none)
      }
      (
        {
          ..model,
          sign_in_dialog: {
            revision: model.sign_in_dialog.revision + 1,
            entry: Some(entry),
          },
        },
        @rabbita.none,
      )
    }
    CloseSignIn(generation, revision) => {
      guard generation == model.generation &&
        revision == model.sign_in_dialog.revision &&
        model.sign_in_dialog.entry is Some(_) else {
        return (model, @rabbita.none)
      }
      (
        { ..model, sign_in_dialog: { revision: revision + 1, entry: None, }, },
        @rabbita.none,
      )
    }
    ToggleFileTreeDrawer => {
      let drawer_open = !model.file_tree.drawer_open
      (
        { ..model, file_tree: { ..model.file_tree, drawer_open, }, },
        @rabbita.none,
      )
    }
    CloseFileTreeDrawer =>
      (
        { ..model, file_tree: { ..model.file_tree, drawer_open: false, }, },
        @rabbita.none,
      )
    FileTreeViewportChanged(width) =>
      if model.file_tree.drawer_open && width >= 768 {
        (
          { ..model, file_tree: { ..model.file_tree, drawer_open: false, }, },
          @rabbita.none,
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
    RetryRoute =>
      match model.route {
        Some(reference) =>
          if reference.target is PullRequest(_) &&
            (model.phase is Showing(_) || model.phase is ShowingPullSelector(_)) {
            if model.access.freshness is Checking {
              (model, @rabbita.none)
            } else {
              (
                { ..model, access: { ..model.access, freshness: Checking, }, },
                shared_snapshot_request(
                  reference,
                  model.generation,
                  emit,
                  revalidate=true,
                ),
              )
            }
          } else {
            begin_change_load(model, reference, emit)
          }
        None => return update_ui(model, Submit, emit)
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
              range: None,
              file_tree: reset_file_tree_state(model.file_tree),
            },
            @rabbita.none,
          )
        Ok(reference) =>
          if model.route == Some(reference) {
            begin_change_load(model, reference, emit)
          } else {
            request_navigation(
              model,
              Path(@routing.playground_route(reference)),
              emit,
            )
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
              range: None,
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
              review: initial_review_state(),
              route: None,
              range: None,
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
      { ..next, access: { ..next.access, identity_checking: false, }, },
      @rabbita.batch([command, auth_status_request(next.auth_revision, emit)]),
    )
  } else {
    (next, command)
  }
}
