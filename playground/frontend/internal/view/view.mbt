///|
fn status_label(status : String) -> String {
  match status {
    "added" => "Added"
    "removed" => "Deleted"
    "renamed" => "Renamed"
    "modified" => "Modified"
    "copied" => "Copied"
    other => other
  }
}

///|
fn status_class(status : String) -> String {
  match status {
    "added" => "file-status status-added"
    "removed" => "file-status status-removed"
    "renamed" => "file-status status-renamed"
    _ => "file-status"
  }
}

///|
fn file_label(file : ApiFile) -> String {
  match file.previous_filename {
    Some(previous) if previous != file.filename =>
      "\{previous} → \{file.filename}"
    _ => file.filename
  }
}

///|
fn source_problem(side : SideLoad) -> String? {
  match side {
    CannotRender(message, _) | LoadFailed(message) => Some(message)
    _ => None
  }
}

///|
fn brand_view() -> @rabbita.Html {
  @html.h1(class="brand", [
    @html.span(class="brand-mark", [
      @html.span(class="mark-plus", "+"),
      @html.span(class="mark-minus", "−"),
    ]),
    @html.span("Moondiff"),
    @html.span(class="brand-suffix", "playground"),
  ])
}

///|
fn commit_form(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.form(on_submit=emit(Ui(Submit)), class="commit-form", [
    @html.label(
      for_="commit-url",
      class="sr-only",
      "Public GitHub commit or pull request URL",
    ),
    @html.div(class="input-row", [
      @html.input(
        id="commit-url",
        input_type=Url,
        value=model.input,
        placeholder="https://github.com/owner/repo/pull/123",
        required=true,
        on_input=value => emit(Ui(InputChanged(value))),
      ),
      @html.button(type_="submit", class="submit-button", [
        @html.span(class="submit-label", "View diff"),
        @html.span(class="submit-arrow", "→"),
      ]),
    ]),
  ])
}

///|
fn route_example() -> @rabbita.Html {
  @html.div(class="route-example", [
    @html.code(class="route-old", [
      @html.span(class="route-prefix", "− github"),
      @html.span(".com/owner/repo/pull/number"),
    ]),
    @html.code(class="route-new", [
      @html.span(class="route-prefix", "+ playground"),
      @html.span("/owner/repo/pull/number"),
    ]),
  ])
}

///|
fn landing_details() -> @rabbita.Html {
  @html.fragment([
    @html.div(class="public-note", [
      @html.span(class="note-dot", ""),
      @html.p(
        "Public repositories work without signing in. Sign in for private repositories and comments.",
      ),
    ]),
    @html.section(class="supported-links", [
      @html.h2("Supported links"),
      @html.ul([
        @html.li([
          @html.span(class="list-arrow", "→"),
          @html.code("github.com/owner/repo/pull/number[/files]"),
        ]),
        @html.li([
          @html.span(class="list-arrow", "→"),
          @html.code("github.com/owner/repo/commit/sha"),
        ]),
        @html.li([
          @html.span(class="list-arrow", "→"),
          @html.code("github.com/owner/repo/pull/number/changes/sha"),
        ]),
      ]),
      @html.p(
        "Commit links stay fixed to their SHA. Pull request links load the latest PR head whenever they are opened.",
      ),
    ]),
  ])
}

///|
fn hero_view(
  model : Model,
  landing : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if landing {
    @html.header(class="hero hero-landing", [
      @html.div(class="hero-copy", [
        brand_view(),
        @html.p(
          class="lede",
          "Review a GitHub commit or an entire pull request, then share the playground URL.",
        ),
        route_example(),
      ]),
      @html.div(class="hero-controls", [
        @html.div(class="input-panel", commit_form(model, emit)),
        landing_details(),
        auth_controls(model.auth, emit),
      ]),
    ])
  } else {
    @html.header(
      class="hero hero-workspace",
      attrs=@html.Attrs::build().inert(model.file_tree.drawer_open),
      [
        @html.div(class="hero-copy", brand_view()),
        @html.div(class="hero-controls", [
          @html.span(class="workspace-url", title=model.input, model.input),
        ]),
        workspace_actions(model, emit),
      ],
    )
  }
}

///|
fn algorithm_control(
  algorithm : DiffAlgorithm,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.div(
    class="segmented-control",
    attrs=@html.Attrs::build().role("group").aria_label("Diff algorithm"),
    [
      @html.button(
        type_="button",
        class=if algorithm is LexicalAlgorithm {
          "segmented-option active"
        } else {
          "segmented-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if algorithm is LexicalAlgorithm {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(Ui(SelectDiffAlgorithm(LexicalAlgorithm))),
        "Token",
      ),
      @html.button(
        type_="button",
        class=if algorithm is AstAlgorithm {
          "segmented-option active"
        } else {
          "segmented-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if algorithm is AstAlgorithm {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(Ui(SelectDiffAlgorithm(AstAlgorithm))),
        "Tree",
      ),
    ],
  )
}

///|
fn layout_control(mode : ViewMode, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.div(
    class="segmented-control",
    attrs=@html.Attrs::build().role("group").aria_label("Diff layout"),
    [ViewMode::Split, Unified].map(option => {
      let selected = mode == option
      @html.button(
        type_="button",
        class=if selected {
          "segmented-option active"
        } else {
          "segmented-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if selected {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(Ui(SelectView(option))),
        match option {
          Split => "Split"
          Unified => "Unified"
        },
      )
    }),
  )
}

///|
fn ignore_comments_control(
  ignore_comments : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.label(
    class=if ignore_comments {
      "toolbar-filter ignore-comments-toggle active"
    } else {
      "toolbar-filter ignore-comments-toggle"
    },
    title=if ignore_comments {
      "Show comment and blank-line changes"
    } else {
      "Ignore MoonBit comment and blank-line changes"
    },
    [
      @html.input(
        input_type=Checkbox,
        checked=ignore_comments,
        attrs=@html.Attrs::build().on_click(_ => emit(Ui(ToggleIgnoreComments))),
      ),
      @html.span(class="ignore-comments-label", "Ignore comments"),
    ],
  )
}

///|
fn ignore_tests_control(
  ignore_tests : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.label(
    class=if ignore_tests {
      "toolbar-filter ignore-tests-toggle active"
    } else {
      "toolbar-filter ignore-tests-toggle"
    },
    title=if ignore_tests {
      "Show MoonBit test files and test blocks"
    } else {
      "Ignore *_test.mbt / *_wbtest.mbt file pairs and top-level MoonBit test and async test blocks"
    },
    [
      @html.input(
        input_type=Checkbox,
        checked=ignore_tests,
        attrs=@html.Attrs::build().on_click(_ => emit(Ui(ToggleIgnoreTests))),
      ),
      @html.span(class="ignore-tests-label", "Ignore tests"),
    ],
  )
}

///|
fn workspace_actions(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  match model.phase {
    Showing(commit) =>
      @html.nav(
        class="workspace-actions",
        attrs=@html.Attrs::build().aria_label("Diff actions"),
        [
          @html.button(
            type_="button",
            class="toolbar-button file-tree-trigger",
            title=if model.file_tree.drawer_open {
              "Close files"
            } else {
              "Browse files"
            },
            attrs=@html.Attrs::build()
              .aria_label(
                if model.file_tree.drawer_open {
                  "Close file tree"
                } else {
                  "Open file tree"
                },
              )
              .aria_expanded(
                if model.file_tree.drawer_open {
                  "true"
                } else {
                  "false"
                },
              )
              .aria_controls("file-tree-sidebar"),
            on_click=emit(Ui(ToggleFileTreeDrawer)),
            [
              @html.span(class="file-tree-trigger-icon", ""),
              @html.span(
                class="file-tree-trigger-count",
                commit.files.length().to_string(),
              ),
            ],
          ),
          @html.div(class="display-controls", [
            algorithm_control(model.diff_algorithm, emit),
            layout_control(model.view_mode, emit),
          ]),
          @html.div(class="filter-controls", [
            ignore_comments_control(model.ignore_comments, emit),
            ignore_tests_control(model.ignore_tests, emit),
          ]),
        ],
      )
    _ => @html.nothing
  }
}

///|
pub(all) struct DiffNotice {
  class_name : String
  label : String
  message : String
}

///|
fn fallback_stage_text(stage : @mbtdiff.ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level alignment"
    SyntaxMatching => "syntax matching"
    IntralineMatching => "intraline matching"
  }
}

///|
fn fallback_sides_text(sides : ArrayView[@mbtdiff.DiffSide]) -> String {
  let names = sides.map(side => {
    match side {
      Old => "old"
      New => "new"
    }
  })
  match names {
    [] => ""
    [side] => "the \{side} side"
    _ => "the \{names.join(" and ")} sides"
  }
}

///|
fn fallback_reason_text(reason : @mbtdiff.FallbackReason) -> String {
  match reason {
    ParseError(detail~, ..) => detail
    SyntaxPositionsOutOfBounds(sides~) => {
      let side_text = fallback_sides_text(sides)
      if side_text.is_empty() {
        "syntax positions out of bounds"
      } else {
        "syntax positions out of bounds on \{side_text}"
      }
    }
    GraphLimitExceeded(limit~) => "graph limit exceeded (\{limit})"
    ComputationLimitExceeded(stage~, limit~) =>
      "computation limit exceeded (\{limit}) during \{fallback_stage_text(stage)}"
  }
}

///|
pub fn diff_notice(
  fallbacks : ArrayView[@mbtdiff.FallbackReason],
  whole : Bool,
) -> DiffNotice? {
  if fallbacks.is_empty() {
    return None
  }
  let reasons = fallbacks.map(fallback_reason_text)
  if whole {
    Some({
      class_name: "diff-notice fallback",
      label: "Lexical fallback",
      message: "AST diff was unavailable, so this entire file is shown using lexical diff. \{reasons.join("; ")}",
    })
  } else {
    Some({
      class_name: "diff-notice partial-fallback",
      label: "Section lexical fallback",
      message: "Only this semantic section uses lexical diff. \{reasons.join("; ")}.",
    })
  }
}

///|
fn diff_notice_view(
  fallbacks : ArrayView[@mbtdiff.FallbackReason],
  whole : Bool,
) -> @rabbita.Html {
  if diff_notice(fallbacks, whole) is Some(notice) {
    @html.div(class=notice.class_name, [
      @html.strong(notice.label),
      @html.span(notice.message),
    ])
  } else {
    @html.nothing
  }
}

///|
fn semantic_range_text(range : @mbtdiff.LineRange) -> String {
  if range.len <= 1 {
    "line \{range.start + 1}"
  } else {
    "lines \{range.start + 1}-\{range.start + range.len}"
  }
}

///|
pub fn semantic_section_fragment(
  section : @mbtdiff.DiffSection,
) -> @mbtdiff.DiffFragment {
  match section {
    Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
  }
}

///|
fn semantic_section_old_range(
  section : @mbtdiff.DiffSection,
) -> @mbtdiff.LineRange? {
  match section {
    Matched(old~, ..) | Deleted(old~, ..) => Some(old)
    Inserted(..) => None
  }
}

///|
fn semantic_section_new_range(
  section : @mbtdiff.DiffSection,
) -> @mbtdiff.LineRange? {
  match section {
    Matched(new~, ..) | Inserted(new~, ..) => Some(new)
    Deleted(..) => None
  }
}

///|
fn semantic_section_old_context(section : @mbtdiff.DiffSection) -> String? {
  match section {
    Matched(old_context~, ..) | Deleted(old_context~, ..) => old_context
    Inserted(..) => None
  }
}

///|
fn semantic_section_new_context(section : @mbtdiff.DiffSection) -> String? {
  match section {
    Matched(new_context~, ..) | Inserted(new_context~, ..) => new_context
    Deleted(..) => None
  }
}

///|
fn semantic_declaration_context_text(
  old_context : String?,
  new_context : String?,
) -> String {
  match (old_context, new_context) {
    (None, None) => ""
    (Some(old), Some(new)) =>
      if old == new {
        old
      } else {
        "old: \{old} → new: \{new}"
      }
    (Some(old), None) => old
    (None, Some(new)) => new
  }
}

///|
pub fn semantic_section_title(
  index : Int,
  section : @mbtdiff.DiffSection,
) -> String {
  let kind = match section {
    Matched(..) => "Matched"
    Deleted(..) => "Deleted"
    Inserted(..) => "Inserted"
  }
  let old = semantic_section_old_range(section)
    .map(range => "old \{semantic_range_text(range)}")
    .unwrap_or("old side absent")
  let new = semantic_section_new_range(section)
    .map(range => "new \{semantic_range_text(range)}")
    .unwrap_or("new side absent")
  let title = "Section #\{index + 1} · \{kind} · \{old} · \{new}"
  let context = semantic_declaration_context_text(
    semantic_section_old_context(section),
    semantic_section_new_context(section),
  )
  if context.is_empty() {
    title
  } else {
    "\{title} · \{context}"
  }
}

///|
fn fragment_has_output(fragment : @mbtdiff.DiffFragment) -> Bool {
  !fragment.document.hunks.is_empty() || !fragment.fallbacks.is_empty()
}

///|
fn semantic_document_has_fallback(document : @mbtdiff.DiffDocument) -> Bool {
  match document {
    Whole(fragment) => !fragment.fallbacks.is_empty()
    TopLevel(top) =>
      top.sections.any(section => {
        !semantic_section_fragment(section).fallbacks.is_empty()
      })
  }
}

///|
fn semantic_fragment_view(
  file : ApiFile,
  file_index : Int,
  section_index : Int?,
  fragment : @mbtdiff.DiffFragment,
  old_range : @mbtdiff.LineRange?,
  new_range : @mbtdiff.LineRange?,
  old_context : String?,
  new_context : String?,
  mode : ViewMode,
  review : Session,
  emit : @rabbita.Emit[Msg],
  whole : Bool,
  expanded? : Bool = true,
  generation? : Int = 0,
  section_key? : String = "",
  on_toggle? : @rabbita.Cmd = @rabbita.none,
  show_hunk_headers? : Bool = true,
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  let title = section_index.map(index => {
    semantic_section_title(
      index,
      match (old_range, new_range) {
        (Some(old), Some(new)) =>
          Matched(old~, new~, old_context~, new_context~, diff=fragment)
        (Some(old), None) => Deleted(old~, old_context~, diff=fragment)
        (None, Some(new)) => Inserted(new~, new_context~, diff=fragment)
        (None, None) => panic()
      },
    )
  })
  let hunk_context = semantic_declaration_context_text(old_context, new_context)
  let old_base = old_range.map(range => range.start).unwrap_or(0)
  let new_base = new_range.map(range => range.start).unwrap_or(0)
  let content = [
    if title is Some(title) {
      @html.summary(
        class="semantic-section-title",
        attrs=@html.Attrs::build().on_click(event => {
          // Summary clicks include native Enter and Space activation.
          event.prevent_default()
          on_toggle
        }),
        [@html.span(class="semantic-section-label", title)],
      )
    } else {
      @html.nothing
    },
    diff_notice_view(fragment.fallbacks, whole),
    if fragment.document.hunks.is_empty() {
      @html.nothing
    } else {
      safe_review_diff(
        file,
        file_index,
        fragment.document,
        mode,
        review,
        emit,
        old_base~,
        new_base~,
        show_hunk_headers~,
        hunk_context~,
        fragment=section_index.map(i => "section:\{i}").unwrap_or("whole"),
        discussions~,
      )
    },
  ]
  if whole {
    @html.section(class="semantic-whole", content)
  } else {
    @html.details(
      class="semantic-section",
      open=expanded,
      attrs=@html.Attrs::build()
        .data_set("section-key", section_key)
        .data_set("navigation-generation", generation.to_string()),
      content,
    )
  }
}

///|
fn top_level_diff_view(
  file : FileState,
  generation : Int,
  file_index : Int,
  top : @mbtdiff.TopLevelDiff,
  mode : ViewMode,
  show_hunk_headers : Bool,
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  let sections : Map[String, @rabbita.Html] = Map([])
  let section_keys = semantic_section_keys(top.sections)
  if top.reordered {
    sections["reorder-notice"] = @html.div(
      class="semantic-reorder",
      "Top-level declarations are reordered; fragment diffs remain paired by declaration identity.",
    )
  }
  for section_index in top.new_order {
    guard top.sections.get(section_index) is Some(section) else { continue }
    if section is Deleted(..) {
      continue
    }
    let fragment = semantic_section_fragment(section)
    if fragment_has_output(fragment) {
      let key = section_keys[section_index]
      sections[key] = semantic_fragment_view(
        file.file,
        file_index,
        Some(section_index),
        fragment,
        semantic_section_old_range(section),
        semantic_section_new_range(section),
        semantic_section_old_context(section),
        semantic_section_new_context(section),
        mode,
        review,
        emit,
        false,
        generation~,
        section_key=key,
        expanded=!file.collapsed_sections.contains(key),
        on_toggle=emit(Load(ToggleSection(generation, file_index, key))),
        show_hunk_headers~,
        discussions~,
      )
    }
  }

  let deleted : Map[String, @rabbita.Html] = Map([])
  for section_index in top.old_order {
    guard top.sections.get(section_index) is Some(section) else { continue }
    if section is Deleted(..) {
      let fragment = semantic_section_fragment(section)
      if fragment_has_output(fragment) {
        let key = section_keys[section_index]
        deleted[key] = semantic_fragment_view(
          file.file,
          file_index,
          Some(section_index),
          fragment,
          semantic_section_old_range(section),
          None,
          semantic_section_old_context(section),
          None,
          mode,
          review,
          emit,
          false,
          generation~,
          section_key=key,
          expanded=!file.collapsed_sections.contains(key),
          on_toggle=emit(Load(ToggleSection(generation, file_index, key))),
          show_hunk_headers~,
          discussions~,
        )
      }
    }
  }
  if !deleted.is_empty() {
    sections["deleted-sections"] = @html.section(
      class="semantic-deleted-group",
      [@html.h4("Deleted declarations (old order)"), @html.div(deleted)],
    )
  }
  @html.div(class="semantic-document", sections)
}

///|
fn semantic_document_view(
  file : FileState,
  generation : Int,
  file_index : Int,
  document : @mbtdiff.DiffDocument,
  mode : ViewMode,
  show_hunk_headers : Bool,
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  match document {
    Whole(fragment) =>
      semantic_fragment_view(
        file.file,
        file_index,
        None,
        fragment,
        None,
        None,
        None,
        None,
        mode,
        review,
        emit,
        true,
        discussions~,
      )
    TopLevel(top) =>
      top_level_diff_view(
        file,
        generation,
        file_index,
        top,
        mode,
        show_hunk_headers,
        review,
        emit,
        discussions~,
      )
  }
}

///|
fn file_diff_view(
  file : FileState,
  generation : Int,
  index : Int,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  let problem = if source_problem(file.old_side) is Some(message) {
    Some(message)
  } else {
    source_problem(file.new_side)
  }
  if problem is Some(message) {
    let retry = file.old_side is LoadFailed(_) || file.new_side is LoadFailed(_)
    return @html.div(class="file-message error", [
      @html.p(message),
      if retry {
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Load(RetryFile(generation, index))),
          "Retry file",
        )
      } else {
        @html.nothing
      },
    ])
  }
  match (file.old_side, file.new_side) {
    (Ready(_), Ready(_)) => {
      guard cached_file_document(
          file,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
        is Some(result) else {
        return @html.p(class="file-message loading-inline", "Preparing diff…")
      }
      match result {
        Line(document) =>
          safe_review_diff(
            file.file,
            index,
            document,
            mode,
            review,
            emit,
            discussions~,
          )
        MoonBit(document~, status~, ignore_reason~) => {
          if status is IgnoredOnly {
            if ignore_reason is Some(TestFile) {
              return @html.div(class="file-message test-file-empty", [
                @html.p(
                  "Test file comparison ignored. Turn off Ignore tests to view this diff.",
                ),
              ])
            }
            let structural = if algorithm is AstAlgorithm {
              "structural "
            } else {
              ""
            }
            let action = if ignore_comments && ignore_tests {
              "Turn off Ignore tests or Ignore comments to view the corresponding filtered changes."
            } else if ignore_tests {
              "Turn off Ignore tests to view test changes."
            } else {
              "Turn off Ignore comments to view comment and blank-line changes."
            }
            return @html.div(class="file-message comment-empty", [
              @html.p(
                "No \{structural}changes besides \{ignored_change_subject(ignore_comments, ignore_tests)} found. \{action}",
              ),
            ])
          }
          if algorithm is AstAlgorithm &&
            status is (Identical | NoStructuralChanges) {
            let structural_empty = @html.div(
              class="file-message structural-empty",
              [
                @html.p(
                  "No structural changes found. Switch to Token to view text changes.",
                ),
              ],
            )
            if semantic_document_visible(document, status, algorithm) {
              return @html.fragment([
                semantic_document_view(
                  file,
                  generation,
                  index,
                  document,
                  mode,
                  true,
                  review,
                  emit,
                  discussions~,
                ),
                structural_empty,
              ])
            }
            return structural_empty
          }
          semantic_document_view(
            file,
            generation,
            index,
            document,
            mode,
            algorithm is AstAlgorithm,
            review,
            emit,
            discussions~,
          )
        }
      }
    }
    (Loading, _) | (_, Loading) =>
      @html.p(class="file-message loading-inline", "Loading file contents…")
    _ => @html.p(class="file-message", "Expand this file to load its diff.")
  }
}

///|
fn file_card(
  file : FileState,
  generation : Int,
  index : Int,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  review : Session,
  emit : @rabbita.Emit[Msg],
  viewed? : @rabbita.Html = @html.nothing,
  viewed_error? : @rabbita.Html = @html.nothing,
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  let toggle_label = if file.expanded { "Collapse" } else { "Expand" }
  @html.article(
    id=file_dom_id(index),
    class=if file.expanded { "file-card expanded" } else { "file-card" },
    [
      @html.div(class="file-heading", [
        @html.div(class="file-name-controls", [
          @html.button(
            type_="button",
            class="file-toggle",
            title="\{toggle_label} \{file_label(file.file)}",
            attrs=@html.Attrs::build()
              .aria_expanded(if file.expanded { "true" } else { "false" })
              .aria_label("\{toggle_label} \{file_label(file.file)}"),
            on_click=emit(Load(ToggleFile(generation, index))),
            [
              @html.span(class="disclosure-icon", ""),
              @html.span(class=status_class(file.file.status), ""),
              @html.code(class="file-path", file_label(file.file)),
            ],
          ),
          file_change_controls(
            file, generation, index, algorithm, ignore_comments, ignore_tests, emit,
          ),
        ]),
        @html.div(class="file-actions", [
          @html.span(class="status-label", status_label(file.file.status)),
          @html.span(class="file-stats", [
            @html.span(class="additions", "+\{file.file.additions}"),
            @html.span(class="deletions", "−\{file.file.deletions}"),
          ]),
          viewed,
        ]),
      ]),
      viewed_error,
      if file.expanded {
        file_diff_view(
          file,
          generation,
          index,
          mode,
          algorithm,
          ignore_comments,
          ignore_tests,
          review,
          emit,
          discussions~,
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn file_list_view(
  commit : ChangeView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if commit.files.length() == 0 {
    return @html.div(
      class="empty-state",
      "No changed files were returned for this change.",
    )
  }
  let file_views : Map[String, @rabbita.Html] = Map([])
  let discussions = prepare_discussions(
    commit,
    model.review,
    emit,
    projection=review_projection(commit, model),
  )
  for index, file in commit.files {
    file_views["file:\{model.generation}:\{file.file.filename}"] = file_card(
      file,
      model.generation,
      index,
      model.view_mode,
      model.diff_algorithm,
      model.ignore_comments,
      model.ignore_tests,
      model.review,
      emit,
      viewed=viewed_checkbox(commit, model, index, emit),
      viewed_error=viewed_file_error(model, index, emit),
      discussions~,
    )
    file_views["discussions:\{model.generation}:\{file.file.filename}"] = file_discussions_view(
      commit,
      index,
      model.review,
      emit,
      discussions~,
    )
  }
  @html.div(class="file-list", file_views)
}

///|
fn change_view(
  commit : ChangeView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let section_label = match commit.reference.target {
    Commit(_) => "GitHub commit"
    PullRequest(_) => "GitHub pull request"
    PullCommit(_, _) => "GitHub pull request commit"
  }
  let identity = match commit.reference.target {
    Commit(_) =>
      "\{commit.reference.owner}/\{commit.reference.repo}@\{commit.sha}"
    PullRequest(number) =>
      "\{commit.reference.owner}/\{commit.reference.repo}#\{number}"
    PullCommit(number, _) =>
      "\{commit.reference.owner}/\{commit.reference.repo}#\{number}@\{commit.sha}"
  }
  let comparison = match commit.reference.target {
    Commit(_) =>
      if commit.parent_sha is Some(parent) {
        "Compared with first parent \{parent}."
      } else {
        "Root commit; compared with an empty tree."
      }
    PullRequest(_) =>
      if commit.parent_sha is Some(parent) {
        "Compared merge base \{parent} with head \{commit.sha}."
      } else {
        "Compared the pull request base with head \{commit.sha}."
      }
    PullCommit(_, _) =>
      if commit.parent_sha is Some(parent) {
        "Compared PR commit \{commit.sha} with first parent \{parent}."
      } else {
        "PR root commit; compared with an empty tree."
      }
  }
  @html.section(class="results", [
    @html.div(
      class="change-layout",
      style=[
        "--file-tree-preferred-width: \{model.file_tree.preferred_width}px",
      ],
      [
        file_tree_view(commit, model, emit),
        file_tree_resizer_view(model.file_tree, emit),
        @html.div(
          class="change-main",
          attrs=@html.Attrs::build().inert(model.file_tree.drawer_open),
          [
            @html.div(class="commit-card", [
              @html.div(class="commit-title", [
                @html.div(class="commit-identity", [
                  @html.p(class="section-label", section_label),
                  @html.a(
                    href=commit.html_url,
                    target=Blank,
                    rel="noopener noreferrer",
                    identity,
                  ),
                  @html.p(class="parent", comparison),
                ]),
                @html.pre(class="commit-message", commit.message),
              ]),
            ]),
            viewed_progress(commit, model, emit),
            comments_overview(commit, model.review, model.auth, emit),
            file_list_view(commit, model, emit),
          ],
        ),
      ],
    ),
  ])
}

///|
fn phase_view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  match model.phase {
    Idle => @html.nothing
    LoadingCommit(page~, ..) =>
      @html.div(class="empty-state loading", [
        @html.span(class="spinner", ""),
        @html.span(
          "Loading commit metadata (page \{page}, up to 100 files per page)…",
        ),
      ])
    LoadingPullMetadata(..) =>
      @html.div(class="empty-state loading", [
        @html.span(class="spinner", ""),
        @html.span("Loading pull request metadata…"),
      ])
    LoadingPullCommitMetadata(..) =>
      @html.div(class="empty-state loading", [
        @html.span(class="spinner", ""),
        @html.span("Loading pull request commit metadata…"),
      ])
    LoadingPullSnapshot(page~, ..) =>
      @html.div(class="empty-state loading", [
        @html.span(class="spinner", ""),
        @html.span(
          if page > 0 {
            "Loading pinned comparison and changed files (page \{page})…"
          } else {
            "Finishing the pinned comparison…"
          },
        ),
      ])
    ValidatingPullSnapshot(..) =>
      @html.div(class="empty-state loading", [
        @html.span(class="spinner", ""),
        @html.span("Checking that the pull request stayed unchanged…"),
      ])
    LoadFailed(message) =>
      @html.div(class="empty-state error", [
        @html.p(message),
        auth_controls(model.auth, emit),
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Ui(Submit)),
          "Try again",
        ),
      ])
    Showing(commit) => change_view(commit, model, emit)
  }
}

///|
fn landing_mode(model : Model) -> Bool {
  match model.phase {
    Idle => true
    LoadFailed(_) => model.route is None
    _ => false
  }
}

///|
pub fn app_view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  let landing = landing_mode(model)
  @html.main_(class=if landing { "shell landing" } else { "shell workspace" }, [
    hero_view(model, landing, emit),
    phase_view(model, emit),
    @html.footer([
      @html.span("Built with Moondiff · "),
      @html.a(
        href="https://github.com/moonbit-community/moondiff",
        target=Blank,
        rel="noopener noreferrer",
        "Source on GitHub",
      ),
    ]),
  ])
}

///|
fn semantic_section_key(section : @mbtdiff.DiffSection) -> String {
  let old = semantic_section_old_range(section)
    .map(r => "\{r.start}:\{r.len}")
    .unwrap_or("-")
  let new = semantic_section_new_range(section)
    .map(r => "\{r.start}:\{r.len}")
    .unwrap_or("-")
  "section:\{old}:\{new}"
}

///|
fn semantic_section_keys(
  sections : ArrayView[@mbtdiff.DiffSection],
) -> Array[String] {
  let occurrences : Map[String, Int] = Map([])
  // Count every section before filtering so visibility cannot renumber siblings.
  sections.map(section => {
    let base = semantic_section_key(section)
    let ordinal = occurrences.get(base).unwrap_or(0)
    occurrences[base] = ordinal + 1
    "\{base}:\{ordinal}"
  })
}
