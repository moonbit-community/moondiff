///|
pub(all) struct DisplayOptions {
  mode : ViewMode
  algorithm : DiffAlgorithm
  ignore_comments : Bool
  ignore_tests : Bool
} derive(Eq)

///|
pub(all) struct FileInput {
  file : FileState
  generation : Int32
  index : Int32
  display : DisplayOptions
  review : @comments.ReadView
  viewed : ViewedControl
  navigation_enabled : Bool
  markdown : MarkdownContext?
}

///|
pub impl Eq for FileInput with fn equal(a, b) {
  @identity.same(a.file, b.file) &&
  a.generation == b.generation &&
  a.index == b.index &&
  a.display == b.display &&
  a.review == b.review &&
  a.viewed == b.viewed &&
  a.navigation_enabled == b.navigation_enabled &&
  a.markdown == b.markdown
}

///|
fn file_input(
  is_pull : Bool,
  model : Model,
  index : Int32,
  file : FileState,
) -> FileInput {
  {
    file,
    generation: model.generation,
    index,
    display: display_options(model),
    review: if model.route
      .map(reference => reference.target is (Range(_, _) | PullRange(_, _, _)))
      .unwrap_or(false) {
      @comments.Session::new().read_view(path=file.file.filename)
    } else {
      model.review.read_view(path=file.file.filename)
    },
    viewed: viewed_control(is_pull, model, index, file.file.filename),
    navigation_enabled: @application.file_navigation_enabled(model, index),
    markdown: markdown_context(model),
  }
}

///|
fn display_options(model : Model) -> DisplayOptions {
  {
    mode: model.view_mode,
    algorithm: model.diff_algorithm,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
  }
}

///|
pub(all) struct ToolbarInput {
  input : String
  landing : Bool
  drawer_open : Bool
  auth : @application.AuthStatus
  file_count : Int32?
  diff_algorithm : DiffAlgorithm
  view_mode : ViewMode
  ignore_comments : Bool
  ignore_tests : Bool
} derive(Eq)

///|
fn toolbar_input(model : Model) -> ToolbarInput {
  {
    input: model.input,
    landing: landing_mode(model),
    drawer_open: model.file_tree.drawer_open,
    auth: model.auth,
    file_count: match model.phase {
      Showing(view) => Some(view.files.length())
      _ => None
    },
    diff_algorithm: model.diff_algorithm,
    view_mode: model.view_mode,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
  }
}

///|
pub(all) struct TreeMetadata {
  path : String
  previous_filename : String?
  status : String
} derive(Eq)

///|
pub struct TreeData {
  priv metadata : Array[TreeMetadata]
  priv rows : Array[FileTreeRow]
  priv statuses : Array[String]
}

///|
pub impl Eq for TreeData with fn equal(a, b) {
  @identity.same(a, b)
}

///|
pub(all) struct TreeInput {
  generation : Int32
  tree : TreeData
  state : FileTreeState
  viewed : Array[Bool]
} derive(Eq)

///|
pub(all) struct NavigationInput {
  generation : Int32
  enabled : Bool
} derive(Eq)

///|
pub(all) struct RebaseMergeInput {
  disabled : Bool
  submitting : Bool
} derive(Eq)

///|
pub(all) struct DiscussionInput {
  generation : Int32
  is_pull : Bool
  review : @comments.ReadView
  auth : @application.AuthStatus
  sign_in_dialog : @application.SignInDialog
  markdown : MarkdownContext?
} derive(Eq)

///|
pub(all) struct PullMergeInput {
  write_enabled : Bool
  state : @application.PullMergeState
  auth : @application.AuthStatus
  snapshot_stale : Bool
} derive(Eq)

///|
pub(all) struct RangePanelInput {
  generation : Int32
  reference : @github.CommitRef
  state : @application.RangeState
  stats : @protocol.ApiStats
  file_count : Int32
} derive(Eq)

///|
pub(all) enum StatusInput {
  Empty
  Loading(String)
  Failed(String, @application.AuthStatus)
  RateLimited(@github_client.RateLimitReason, @application.AuthStatus)
} derive(Eq)

///|
pub(all) enum RegionInput {
  Home(@application.AuthStatus, @application.HomeState)
  Toolbar(ToolbarInput)
  Status(StatusInput)
  FileTree(TreeInput)
  Navigation(NavigationInput)
  ViewedSummary(ViewedSummaryInput)
  Discussion(DiscussionInput)
  PullMergeStatus(PullMergeInput)
  RangePanel(RangePanelInput)
  File(FileInput)
} derive(Eq)

///|
pub(all) struct ShellInput {
  home : Bool
  generation : Int32
  landing : Bool
  showing : Bool
  selector_only : Bool
  message : String
  pull_body : String?
  pull_user : @protocol.ApiCommentUser?
  markdown : MarkdownContext?
  drawer_open : Bool
  preferred_width : Int32
  display : DisplayOptions
  range_limit : Bool
} derive(Eq)

///|
pub fn shell_input(model : Model) -> ShellInput {
  {
    home: home_shell(model),
    generation: model.generation,
    landing: landing_mode(model),
    showing: model.phase is Showing(_),
    selector_only: model.phase is ShowingPullSelector(_),
    message: match model.phase {
      Showing(view) => view.message
      _ => ""
    },
    pull_body: match model.phase {
      Showing(view) => view.pull_snapshot.bind(pull => pull.body)
      ShowingPullSelector(pull) => pull.body
      _ => None
    },
    pull_user: match model.phase {
      Showing(view) => view.pull_snapshot.bind(pull => pull.user)
      ShowingPullSelector(pull) => pull.user
      _ => None
    },
    markdown: markdown_context(model),
    drawer_open: model.file_tree.drawer_open,
    preferred_width: model.file_tree.preferred_width,
    display: display_options(model),
    range_limit: model.route
    .map(reference => {
      reference.target is (Range(_, _) | PullRange(_, _, _)) &&
      model.range.map(r => r.too_many_files).unwrap_or(false)
    })
    .unwrap_or(false),
  }
}

///|
pub struct RegionProjection {
  priv mut tree : TreeData?
  priv mut overall : (Int32, Int32, TreeData, @comments.CommentGroup)?
}

///|
pub fn RegionProjection::new() -> RegionProjection {
  { tree: None, overall: None, }
}

///|
pub fn RegionProjection::inputs(
  self : RegionProjection,
  model : Model,
) -> Array[(@application.Region, RegionInput)] {
  if home_shell(model) {
    self.tree = None
    self.overall = None
    return [(Home, Home(model.auth, model.home))]
  }
  let inputs : Array[(@application.Region, RegionInput)] = [
    (Toolbar, Toolbar(toolbar_input(model))),
    (Status, Status(status_input(model))),
  ]
  if model.phase is ShowingPullSelector(pull) &&
    model.route is Some(reference) &&
    model.range is Some(state) {
    self.tree = None
    self.overall = None
    inputs.push(
      (
        RangePanel,
        RangePanel({
          generation: model.generation,
          reference,
          state,
          stats: @github.pull_stats(pull),
          file_count: pull.changed_files,
        }),
      ),
    )
    return inputs
  }
  guard model.phase is Showing(view) else {
    self.tree = None
    self.overall = None
    return inputs
  }
  let metadata = view.files.map(f => TreeMetadata::{
    path: f.file.filename,
    previous_filename: f.file.previous_filename,
    status: f.file.status,
  })
  let tree = match self.tree {
    Some(tree) if tree.metadata == metadata => tree
    _ => {
      let statuses : Array[String] = []
      for file in metadata {
        if !statuses.contains(file.status) {
          statuses.push(file.status)
        }
      }
      let tree = TreeData::{
        metadata,
        rows: build_file_tree_metadata(metadata),
        statuses,
      }
      self.tree = Some(tree)
      tree
    }
  }
  let is_pull = view.reference.target is PullRequest(_)
  let is_range = view.reference.target is (Range(_, _) | PullRange(_, _, _))
  if model.range is Some(state) {
    inputs.push(
      (
        RangePanel,
        RangePanel({
          generation: model.generation,
          reference: view.reference,
          state,
          stats: view.stats,
          file_count: view.files.length(),
        }),
      ),
    )
  }
  inputs.push(
    (
      FileTree,
      FileTree({
        generation: model.generation,
        tree,
        state: model.file_tree,
        viewed: model.viewed.files.map(f => f.state is Some(Viewed)),
      }),
    ),
  )
  let mut enabled = false
  for index, file in view.files {
    let input = file_input(is_pull, model, index, file)
    enabled = enabled || input.navigation_enabled
    inputs.push((File(file.file.filename), File(input)))
  }
  inputs.push(
    (Navigation, Navigation({ generation: model.generation, enabled, })),
  )
  if !is_range {
    inputs.push(
      (
        ViewedSummary,
        ViewedSummary(viewed_summary_input(is_pull, view.files.length(), model)),
      ),
    )
  }
  let paths = metadata.map(f => f.path)
  let group = match self.overall {
    Some((generation, version, old_tree, group)) if generation ==
      model.generation &&
      version == model.review.comment_version() &&
      @identity.same(tree, old_tree) => group
    _ => {
      let group = model.review.overall_comments(paths)
      self.overall = Some(
        (model.generation, model.review.comment_version(), tree, group),
      )
      group
    }
  }
  if !is_range {
    inputs.push(
      (
        Discussion,
        Discussion({
          generation: model.generation,
          is_pull,
          review: model.review.read_view(paths~, group~),
          auth: model.auth,
          sign_in_dialog: model.sign_in_dialog,
          markdown: markdown_context(model),
        }),
      ),
    )
  }
  if is_pull {
    inputs.push(
      (
        PullMergeStatus,
        PullMergeStatus({
          state: model.pull_merge,
          auth: model.auth,
          snapshot_stale: model.review.snapshot_stale,
          write_enabled: @application.writes_allowed(model),
        }),
      ),
    )
  }
  inputs
}

///|
fn status_input(model : Model) -> StatusInput {
  if model.source_pause is Some(reason) {
    return RateLimited(reason, model.auth)
  }
  if model.phase is Showing(_) || model.phase is ShowingPullSelector(_) {
    return match model.access.freshness {
      Checking => Loading("Checking the current PR version…")
      Unavailable(message) =>
        if model.auth is AuthFailed(_) && model.phase is Showing(_) {
          // The discussion already owns the session error and sign-in action.
          Empty
        } else {
          Failed(message, model.auth)
        }
      Confirmed => Empty
    }
  }
  match model.phase {
    Idle =>
      if model.route is Some(_) {
        Loading("Checking GitHub session…")
      } else {
        Empty
      }
    LoadFailed(message) => Failed(message, model.auth)
    LoadingCommit(page~, ..) =>
      Loading(
        "Loading commit metadata (page \{page}, up to 100 files per page)…",
      )
    LoadingPullMetadata(..) => Loading("Loading pull request metadata…")
    LoadingPullCommitMetadata(..) =>
      Loading("Loading pull request commit metadata…")
    LoadingRangePullMetadata(..) =>
      Loading("Loading pull request context for this commit interval…")
    LoadingRangePullCompare(..) =>
      Loading("Finding the pull request merge base…")
    LoadingRange(..) => Loading("Loading commit interval…")
    LoadingPullSnapshot(page~, ..) =>
      Loading(
        if page > 0 {
          "Loading pinned comparison and changed files (page \{page})…"
        } else {
          "Finishing the pinned comparison…"
        },
      )
    ValidatingPullSnapshot(..) =>
      Loading("Checking that the pull request stayed unchanged…")
    LoadingPullSelectorCompare(..) =>
      Loading("Finding the pull request merge base…")
    ValidatingPullSelector(..) =>
      Loading("Checking that the pull request stayed unchanged…")
    ShowingPullSelector(_) => Empty
    Showing(_) => Empty
  }
}

///|
fn home_shell(model : Model) -> Bool {
  model.route is None &&
  model.phase is Idle &&
  model.auth is (AuthChecking | SignedIn(..))
}

///|
pub(all) struct ViewedControl {
  is_pull : Bool
  requires_sign_in : Bool
  generation : Int32
  index : Int32
  path : String
  checked : Bool
  syncing : Bool
  confirming : Bool
  dismissed : Bool
  disabled : Bool
  title : String
  error : String?
  retry_disabled : Bool
} derive(Eq)

///|
pub(all) struct ViewedSummaryInput {
  is_pull : Bool
  total : Int32
  count : Int32
  pending : Bool
  auth : @application.AuthStatus
  ready : Bool
  loading : Bool
  error : String?
  stale : Bool
  can_refresh : Bool
  poll_scheduled : Bool
} derive(Eq)
