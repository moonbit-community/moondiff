///|
pub(all) struct FileTreeState {
  drawer_open : Bool
  search_open : Bool
  search_query : String
  selected_statuses : Array[String]
  collapsed_directories : Array[String]
  selected_file_index : Int?
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
  }
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
