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
  generation : Int
  index : Int
  display : DisplayOptions
  review : @comments.ReadView
  viewed : ViewedControl
  navigation_enabled : Bool
}

///|
pub impl Eq for FileInput with fn equal(a, b) {
  @identity.same(a.file, b.file) &&
  a.generation == b.generation &&
  a.index == b.index &&
  a.display == b.display &&
  a.review == b.review &&
  a.viewed == b.viewed &&
  a.navigation_enabled == b.navigation_enabled
}

///|
fn file_input(
  is_pull : Bool,
  model : Model,
  index : Int,
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
  file_count : Int?
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
  generation : Int
  tree : TreeData
  state : FileTreeState
  viewed : Array[Bool]
} derive(Eq)

///|
pub(all) struct NavigationInput {
  generation : Int
  enabled : Bool
} derive(Eq)

///|
pub(all) struct DiscussionInput {
  is_pull : Bool
  review : @comments.ReadView
  auth : @application.AuthStatus
} derive(Eq)

///|
pub(all) struct PullMergeInput {
  state : @application.PullMergeState
  auth : @application.AuthStatus
  snapshot_stale : Bool
} derive(Eq)

///|
pub(all) struct RangePanelInput {
  reference : @github.CommitRef
  state : @application.RangeState
  stats : @protocol.ApiStats
  file_count : Int
} derive(Eq)

///|
pub(all) enum StatusInput {
  Empty
  Loading(String)
  Failed(String, @application.AuthStatus)
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
  generation : Int
  landing : Bool
  showing : Bool
  selector_only : Bool
  message : String
  drawer_open : Bool
  preferred_width : Int
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
  priv mut overall : (Int, Int, TreeData, @comments.CommentGroup)?
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
    let status : StatusInput = match model.phase {
      Idle => Empty
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
    inputs.push((Status, Status(status)))
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
          is_pull,
          review: model.review.read_view(paths~, group~),
          auth: model.auth,
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
        }),
      ),
    )
  }
  inputs
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
  generation : Int
  index : Int
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
  total : Int
  count : Int
  pending : Bool
  auth : @application.AuthStatus
  ready : Bool
  loading : Bool
  error : String?
  stale : Bool
  poll_scheduled : Bool
} derive(Eq)
