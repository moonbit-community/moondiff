///|
pub(all) enum Region {
  Home
  Shell
  Toolbar
  Status
  FileTree
  Navigation
  ViewedSummary
  Discussion
  File(String)
} derive(Eq, Hash)

///|
pub fn Region::key(self : Region) -> String {
  match self {
    Home => "home"
    Shell => "shell"
    Toolbar => "toolbar"
    Status => "status"
    FileTree => "tree"
    Navigation => "navigation"
    ViewedSummary => "viewed"
    Discussion => "discussion"
    File(path) => "file:\{path}"
  }
}

///|
pub(all) enum NavigationPolicy {
  Cancel
  Continue
} derive(Eq)

///|
pub(all) enum CommitScope {
  Region
  PageLayout
} derive(Eq)

///|
pub(all) struct AfterCommit {
  target : Region
  scope : CommitScope
  command : @rabbita.Cmd
  navigation : NavigationPolicy
}

///|
pub(all) struct Transition {
  model : Model
  command : @rabbita.Cmd
  after_commit : Array[AfterCommit]
}

///|
fn ui_after_commit(
  before : Model,
  next : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> Array[AfterCommit] {
  let actions : Array[AfterCommit] = []
  fn focus(target : Region, selector : String) {
    actions.push({
      target,
      scope: Region,
      command: focus_selector(selector),
      navigation: Cancel,
    })
  }
  if msg
    is Ui(
      ToggleFileTreeDrawer
      | CloseFileTreeDrawer
      | FileTreeViewportChanged(_)
    ) &&
    before.file_tree.drawer_open != next.file_tree.drawer_open {
    if next.file_tree.drawer_open {
      focus(FileTree, "#file-tree-sidebar .drawer-close")
    } else if msg is Ui(FileTreeViewportChanged(_)) {
      focus(FileTree, "#file-tree-sidebar .search-toggle")
    } else {
      focus(Toolbar, ".file-tree-trigger")
    }
  }
  if next.phase is Showing(view) {
    match msg {
      Load(OpenFile(generation, index)) if generation == next.generation &&
        view.files.get(index) is Some(file) =>
        actions.push({
          target: File(file.file.filename),
          scope: PageLayout,
          command: scroll_file(file_dom_id(index), before.file_tree.drawer_open),
          navigation: Cancel,
        })
      Load(NavigateChange(generation, index, key, block, direction)) if generation ==
        next.generation &&
        view.files.get(index) is Some(file) &&
        file_navigation_enabled(next, index) &&
        block >= 0 &&
        (direction == -1 || direction == 1) =>
        actions.push({
          target: File(file.file.filename),
          scope: PageLayout,
          command: navigate_change_after_commit(
            generation, index, key, block, direction,
          ),
          navigation: Cancel,
        })
      Viewed(Toggle(generation, index)) if generation == next.generation &&
        view.files.get(index) is Some(file) &&
        next.viewed.files.get(index) is Some({ pending: Some(pending), .. }) &&
        before.viewed.files
        .get(index)
        .map(f => f.pending is None)
        .unwrap_or(false) =>
        actions.push({
          target: File(file.file.filename),
          scope: Region,
          command: viewed_persist_request(next, index, pending.record, emit),
          navigation: Continue,
        })
      _ => ()
    }
  }
  actions
}

///|
fn scroll_file(id : String, focus : Bool) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => scroll_file_now(id, focus))
}

///|
extern "js" fn scroll_file_now(id : String, focus : Bool) -> Unit =
  #| (id, focus) => {
  #|   const file = document.getElementById(id);
  #|   file?.scrollIntoView({ block: 'start', behavior: 'instant' });
  #|   if (focus) file?.querySelector('.file-toggle')?.focus({ preventScroll: true });
  #| }
