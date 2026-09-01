///|
enum FileTreeRow {
  TreeDirectory(path~ : String, name~ : String, depth~ : Int)
  TreeFile(
    index~ : Int,
    path~ : String,
    name~ : String,
    depth~ : Int,
    status~ : String,
    previous_path~ : String?
  )
} derive(Eq, Debug)

///|
priv enum FileTreeNode {
  TreeNodeDirectory(path~ : String, name~ : String)
  TreeNodeFile(
    index~ : Int,
    path~ : String,
    name~ : String,
    status~ : String,
    previous_path~ : String?
  )
}

///|
priv struct FileTreeProjection {
  visible_rows : Array[FileTreeRow]
  matching_count : Int
}

///|
fn file_tree_path_parts(path : String) -> Array[String] {
  path
  .split("/")
  .filter(part => !part.is_empty())
  .map(StringView::to_owned)
  .collect()
}

///|
fn file_tree_children_for(
  children : Map[String, Array[FileTreeNode]],
  parent : String,
) -> Array[FileTreeNode] {
  match children.get(parent) {
    Some(nodes) => nodes
    None => {
      let nodes : Array[FileTreeNode] = []
      children[parent] = nodes
      nodes
    }
  }
}

///|
fn append_file_tree_rows(
  parent : String,
  depth : Int,
  children : Map[String, Array[FileTreeNode]],
  rows : Array[FileTreeRow],
) -> Unit {
  guard children.get(parent) is Some(nodes) else { return }
  for node in nodes {
    match node {
      TreeNodeDirectory(path~, name~) => {
        rows.push(TreeDirectory(path~, name~, depth~))
        append_file_tree_rows(path, depth + 1, children, rows)
      }
      TreeNodeFile(index~, path~, name~, status~, previous_path~) =>
        rows.push(
          TreeFile(index~, path~, name~, depth~, status~, previous_path~),
        )
    }
  }
}

///|
fn build_file_tree(files : ArrayView[FileState]) -> Array[FileTreeRow] {
  let children : Map[String, Array[FileTreeNode]] = Map([])
  let seen_directories : Map[String, Unit] = Map([])
  for index, state in files {
    let file = state.file
    let parts = file_tree_path_parts(file.filename)
    let mut parent_path = ""
    let mut directory_path = ""
    for part_index in 0..<(parts.length() - 1) {
      let part = parts[part_index]
      directory_path = if directory_path.is_empty() {
        part
      } else {
        "\{directory_path}/\{part}"
      }
      if !seen_directories.contains(directory_path) {
        seen_directories[directory_path] = ()
        file_tree_children_for(children, parent_path).push(
          TreeNodeDirectory(path=directory_path, name=part),
        )
      }
      parent_path = directory_path
    }
    let name = parts.last().unwrap_or(file.filename)
    file_tree_children_for(children, parent_path).push(
      TreeNodeFile(
        index~,
        path=file.filename,
        name~,
        status=file.status,
        previous_path=file.previous_filename,
      ),
    )
  }
  let rows : Array[FileTreeRow] = []
  append_file_tree_rows("", 0, children, rows)
  rows
}

///|
fn file_tree_statuses(files : ArrayView[FileState]) -> Array[String] {
  let statuses : Array[String] = []
  for state in files {
    if !statuses.contains(state.file.status) {
      statuses.push(state.file.status)
    }
  }
  statuses
}

///|
fn file_tree_filters_active(state : FileTreeState) -> Bool {
  !state.search_query.trim().is_empty() || !state.selected_statuses.is_empty()
}

///|
fn file_tree_file_matches(
  path : String,
  previous_path : String?,
  status : String,
  selected_statuses : ArrayView[String],
  query : String,
) -> Bool {
  let status_matches = selected_statuses.is_empty() ||
    selected_statuses.contains(status)
  if !status_matches {
    return false
  }
  query.is_empty() ||
  path.to_lower().contains(query) ||
  previous_path.map(old => old.to_lower().contains(query)).unwrap_or(false)
}

///|
fn file_tree_path_is_descendant(path : String, directory : String) -> Bool {
  path.has_prefix("\{directory}/")
}

///|
fn remember_file_tree_ancestors(
  path : String,
  ancestors : Map[String, Unit],
) -> Unit {
  let parts = file_tree_path_parts(path)
  if parts.length() <= 1 {
    return
  }
  let mut directory_path = ""
  for part_index in 0..<(parts.length() - 1) {
    let part = parts[part_index]
    directory_path = if directory_path.is_empty() {
      part
    } else {
      "\{directory_path}/\{part}"
    }
    ancestors[directory_path] = ()
  }
}

///|
fn file_tree_hidden_by_collapse(
  path : String,
  collapsed_directories : ArrayView[String],
  directory_row : Bool,
) -> Bool {
  collapsed_directories.any(directory => {
    file_tree_path_is_descendant(path, directory) &&
    (!directory_row || path != directory)
  })
}

///|
fn project_file_tree(
  rows : ArrayView[FileTreeRow],
  state : FileTreeState,
) -> FileTreeProjection {
  let filtering = file_tree_filters_active(state)
  let visible_rows : Array[FileTreeRow] = []
  if filtering {
    let query = state.search_query.trim().to_owned().to_lower()
    let matching_files : Map[Int, Unit] = Map([])
    let matching_directories : Map[String, Unit] = Map([])
    let mut matching_count = 0
    for row in rows {
      match row {
        TreeFile(index~, path~, status~, previous_path~, ..) =>
          if file_tree_file_matches(
              path,
              previous_path,
              status,
              state.selected_statuses,
              query,
            ) {
            matching_files[index] = ()
            remember_file_tree_ancestors(path, matching_directories)
            matching_count += 1
          }
        TreeDirectory(..) => ()
      }
    }
    for row in rows {
      match row {
        TreeDirectory(path~, ..) =>
          if matching_directories.contains(path) {
            visible_rows.push(row)
          }
        TreeFile(index~, ..) =>
          if matching_files.contains(index) {
            visible_rows.push(row)
          }
      }
    }
    { visible_rows, matching_count, }
  } else {
    let mut matching_count = 0
    for row in rows {
      match row {
        TreeDirectory(path~, ..) =>
          if !file_tree_hidden_by_collapse(
              path,
              state.collapsed_directories,
              true,
            ) {
            visible_rows.push(row)
          }
        TreeFile(path~, ..) => {
          matching_count += 1
          if !file_tree_hidden_by_collapse(
              path,
              state.collapsed_directories,
              false,
            ) {
            visible_rows.push(row)
          }
        }
      }
    }
    { visible_rows, matching_count, }
  }
}

///|
fn file_tree_status_marker(status : String) -> String {
  match status {
    "added" => "A"
    "modified" => "M"
    "removed" => "D"
    "renamed" => "R"
    "copied" => "C"
    _ => "?"
  }
}

///|
fn file_tree_status_class(status : String) -> String {
  match status {
    "added" => "tree-file-status tree-status-added"
    "removed" => "tree-file-status tree-status-removed"
    "renamed" => "tree-file-status tree-status-renamed"
    "copied" => "tree-file-status tree-status-copied"
    _ => "tree-file-status tree-status-modified"
  }
}

///|
fn file_tree_row_view(
  row : FileTreeRow,
  state : FileTreeState,
  generation : Int,
  filtering : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match row {
    TreeDirectory(path~, name~, depth~) => {
      let expanded = filtering || !state.collapsed_directories.contains(path)
      @html.button(
        type_="button",
        class="file-tree-row directory-row",
        style=["padding-left: \{10 + depth * 14}px"],
        title=if filtering {
          "Clear filters to collapse \{path}"
        } else if expanded {
          "Collapse \{path}"
        } else {
          "Expand \{path}"
        },
        disabled=filtering,
        attrs=@html.Attrs::build()
          .role("treeitem")
          .aria_level((depth + 1).to_string())
          .aria_expanded(if expanded { "true" } else { "false" })
          .aria_disabled(if filtering { "true" } else { "false" })
          .aria_label(
            if filtering {
              "Directory \{path}, expanded while filtering"
            } else if expanded {
              "Collapse directory \{path}"
            } else {
              "Expand directory \{path}"
            },
          ),
        on_click=if filtering {
          @rabbita.none
        } else {
          emit(Ui(ToggleFileTreeDirectory(path)))
        },
        [
          @html.span(class="tree-disclosure", ""),
          @html.span(class="tree-directory-icon", ""),
          @html.span(class="tree-row-name", name),
        ],
      )
    }
    TreeFile(index~, path~, name~, depth~, status~, previous_path~) => {
      let selected = state.selected_file_index == Some(index)
      let renamed = previous_path.filter(old => old != path)
      @html.button(
        type_="button",
        class=if selected {
          "file-tree-row file-row selected"
        } else {
          "file-tree-row file-row"
        },
        style=["padding-left: \{24 + depth * 14}px"],
        title=renamed
          .map(old => "\{path} — renamed from \{old}")
          .unwrap_or(path),
        attrs=@html.Attrs::build()
          .role("treeitem")
          .aria_level((depth + 1).to_string())
          .aria_selected(if selected { "true" } else { "false" })
          .aria_label(
            renamed
            .map(old => "Open \{path}, renamed from \{old}")
            .unwrap_or("Open \{path}"),
          ),
        on_click=emit(Load(OpenFile(generation, index))),
        [
          @html.span(
            class=file_tree_status_class(status),
            attrs=@html.Attrs::build().aria_hidden("true"),
            file_tree_status_marker(status),
          ),
          @html.span(class="tree-row-name", name),
        ],
      )
    }
  }
}

///|
fn file_tree_status_filters(
  statuses : ArrayView[String],
  state : FileTreeState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if statuses.length() <= 1 {
    return @html.nothing
  }
  @html.div(
    class="file-tree-status-filters",
    attrs=@html.Attrs::build().role("group").aria_label("Filter by file status"),
    statuses.map(status => {
      let selected = state.selected_statuses.contains(status)
      @html.button(
        type_="button",
        class=if selected {
          "tree-status-filter active"
        } else {
          "tree-status-filter"
        },
        title="Filter \{status_label(status).to_lower()} files",
        attrs=@html.Attrs::build()
          .aria_label("Filter \{status_label(status).to_lower()} files")
          .aria_pressed(if selected { "true" } else { "false" }),
        on_click=emit(Ui(ToggleFileTreeStatus(status))),
        [
          @html.span(
            class=file_tree_status_class(status),
            file_tree_status_marker(status),
          ),
          @html.span(class="tree-status-name", status_label(status)),
        ],
      )
    }),
  )
}

///|
extern "js" fn trap_file_tree_tab(event : @dom.KeyboardEvent) -> Unit =
  #| (event) => {
  #|   if (event.key !== "Tab") return
  #|   const sidebar = event.currentTarget
  #|   if (!(sidebar instanceof HTMLElement)) return
  #|   const selector = [
  #|     "a[href]",
  #|     "button:not([disabled])",
  #|     "input:not([disabled])",
  #|     "select:not([disabled])",
  #|     "textarea:not([disabled])",
  #|     '[tabindex]:not([tabindex="-1"])',
  #|   ].join(",")
  #|   const focusable = Array.from(sidebar.querySelectorAll(selector)).filter(element => {
  #|     if (!(element instanceof HTMLElement) || element.hidden) return false
  #|     const style = getComputedStyle(element)
  #|     return style.display !== "none" && style.visibility !== "hidden"
  #|   })
  #|   if (focusable.length === 0) return
  #|   const first = focusable[0]
  #|   const last = focusable[focusable.length - 1]
  #|   if (event.shiftKey && document.activeElement === first) {
  #|     event.preventDefault()
  #|     last.focus({ preventScroll: true })
  #|   } else if (!event.shiftKey && document.activeElement === last) {
  #|     event.preventDefault()
  #|     first.focus({ preventScroll: true })
  #|   }
  #| }

///|
fn file_tree_drawer_keydown(
  event : @dom.KeyboardEvent,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match event.key() {
    "Escape" => {
      event.prevent_default()
      emit(Ui(CloseFileTreeDrawer))
    }
    "Tab" => {
      trap_file_tree_tab(event)
      @rabbita.none
    }
    _ => @rabbita.none
  }
}

///|
fn file_tree_view(
  commit : ChangeView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let rows = build_file_tree(commit.files)
  let projection = project_file_tree(rows, model.file_tree)
  let filtering = file_tree_filters_active(model.file_tree)
  let statuses = file_tree_statuses(commit.files)
  @html.fragment([
    @html.button(
      type_="button",
      class="file-tree-backdrop",
      hidden=!model.file_tree.drawer_open,
      attrs=@html.Attrs::build().aria_label("Close file tree").tabindex(-1),
      on_click=emit(Ui(CloseFileTreeDrawer)),
      "",
    ),
    @html.aside(
      id="file-tree-sidebar",
      class=if model.file_tree.drawer_open {
        "file-tree-sidebar open"
      } else {
        "file-tree-sidebar"
      },
      attrs=if model.file_tree.drawer_open {
        @html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label("Changed files")
        .on_keydown(event => file_tree_drawer_keydown(event, emit))
      } else {
        @html.Attrs::build().role("complementary").aria_label("Changed files")
      },
      [
        @html.div(class="file-tree-header", [
          @html.div(class="file-tree-heading", [
            @html.h2("Files"),
            @html.span(
              class="file-tree-count",
              if filtering {
                "\{projection.matching_count}/\{commit.files.length()}"
              } else {
                commit.files.length().to_string()
              },
            ),
          ]),
          @html.div(class="file-tree-actions", [
            @html.button(
              type_="button",
              class=if model.file_tree.search_open {
                "file-tree-action search-toggle active"
              } else {
                "file-tree-action search-toggle"
              },
              title=if model.file_tree.search_open {
                "Close search"
              } else {
                "Search files"
              },
              attrs=@html.Attrs::build()
                .aria_label(
                  if model.file_tree.search_open {
                    "Close file search"
                  } else {
                    "Search files"
                  },
                )
                .aria_expanded(
                  if model.file_tree.search_open {
                    "true"
                  } else {
                    "false"
                  },
                )
                .aria_controls("file-tree-search"),
              on_click=emit(Ui(ToggleFileTreeSearch)),
              @html.span(class="tree-search-icon", ""),
            ),
            @html.button(
              type_="button",
              class="file-tree-action drawer-close",
              attrs=@html.Attrs::build().aria_label("Close file tree"),
              on_click=emit(Ui(CloseFileTreeDrawer)),
              "×",
            ),
          ]),
        ]),
        if model.file_tree.search_open {
          @html.div(class="file-tree-search", [
            @html.label(
              for_="file-tree-search",
              class="sr-only",
              "Search changed files",
            ),
            @html.input(
              id="file-tree-search",
              input_type=Search,
              value=model.file_tree.search_query,
              placeholder="Search paths",
              autofocus=true,
              attrs=@html.Attrs::build().aria_label("Search changed files"),
              on_input=query => emit(Ui(FileTreeSearchChanged(query))),
            ),
          ])
        } else {
          @html.nothing
        },
        file_tree_status_filters(statuses, model.file_tree, emit),
        @html.div(
          class="file-tree-scroll",
          attrs=@html.Attrs::build()
            .role("tree")
            .aria_label("Changed file tree"),
          if projection.matching_count == 0 {
            @html.p(class="file-tree-empty", "No matching files.")
          } else {
            @html.fragment(
              projection.visible_rows.map(row => {
                file_tree_row_view(
                  row,
                  model.file_tree,
                  model.generation,
                  filtering,
                  emit,
                )
              }),
            )
          },
        ),
      ],
    ),
  ])
}
