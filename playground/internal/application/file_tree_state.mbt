///|
pub(all) struct FileTreeState {
  drawer_open : Bool
  search_open : Bool
  search_query : String
  selected_statuses : Array[String]
  collapsed_directories : Array[String]
  selected_file_index : Int?
  preferred_width : Int
} derive(Eq)

///|
fn initial_file_tree_state() -> FileTreeState {
  {
    drawer_open: false,
    search_open: false,
    search_query: "",
    selected_statuses: [],
    collapsed_directories: [],
    selected_file_index: None,
    preferred_width: 320,
  }
}

///|
fn reset_file_tree_state(state : FileTreeState) -> FileTreeState {
  { ..initial_file_tree_state(), preferred_width: state.preferred_width, }
}

///|
fn normalize_file_tree_width(width : Int) -> Int {
  if width < 240 {
    240
  } else if width > 640 {
    640
  } else {
    width
  }
}

///|
pub fn file_dom_id(index : Int) -> String {
  "moondiff-file-\{index}"
}

///|
fn toggle_file_tree_value(
  values : Array[String],
  value : String,
) -> Array[String] {
  if values.contains(value) {
    values.filter(item => item != value)
  } else {
    let changed = values.copy()
    changed.push(value)
    changed
  }
}
