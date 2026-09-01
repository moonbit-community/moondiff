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
      @html.span("/#/owner/repo/pull/number"),
    ]),
  ])
}

///|
fn landing_details() -> @rabbita.Html {
  @html.fragment([
    @html.div(class="public-note", [
      @html.span(class="note-dot", ""),
      @html.p("Public repositories only."),
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
          "Review a public GitHub commit or an entire pull request, then share the playground URL with anyone.",
        ),
        route_example(),
      ]),
      @html.div(class="hero-controls", [
        @html.div(class="input-panel", commit_form(model, emit)),
        landing_details(),
      ]),
    ])
  } else {
    @html.header(class="hero hero-workspace", [
      @html.div(class="hero-copy", brand_view()),
      @html.div(class="hero-controls", [
        @html.div(class="input-panel", commit_form(model, emit)),
      ]),
      workspace_actions(model, emit),
    ])
  }
}

///|
fn copy_button_label(status : CopyStatus) -> String {
  match status {
    CopyReady => "Copy link"
    Copied => "Copied"
    CopyError(_) => "Try copy again"
  }
}

///|
fn share_control(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  if model.share_url is Some(url) {
    let label = copy_button_label(model.copy_status)
    @html.fragment([
      @html.div(class="share-accessibility", [
        @html.label(for_="share-url", "Shareable playground URL"),
        @html.input(
          id="share-url",
          value=url,
          read_only=true,
          class="share-url",
          attrs=@html.Attrs::build().tabindex(-1),
        ),
      ]),
      @html.button(
        type_="button",
        class=if model.copy_status is Copied {
          "toolbar-button copy-button copied"
        } else {
          "toolbar-button copy-button"
        },
        title=match model.copy_status {
          CopyError(message) => "Clipboard access failed: \{message}"
          _ => label
        },
        attrs=@html.Attrs::build().aria_label(label),
        on_click=emit(Ui(CopyShareLink)),
        [
          @html.span(class="copy-icon", ""),
          @html.span(class="copy-label", label),
        ],
      ),
    ])
  } else {
    @html.nothing
  }
}

///|
fn algorithm_control(
  algorithm : DiffAlgorithm,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.div(
    class="algorithm-toggle",
    attrs=@html.Attrs::build().role("group").aria_label("Diff algorithm"),
    [
      @html.button(
        type_="button",
        class=if algorithm is LexicalAlgorithm {
          "algorithm-option active"
        } else {
          "algorithm-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if algorithm is LexicalAlgorithm {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(Ui(SelectDiffAlgorithm(LexicalAlgorithm))),
        "Lexical",
      ),
      @html.button(
        type_="button",
        class=if algorithm is AstAlgorithm {
          "algorithm-option active"
        } else {
          "algorithm-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if algorithm is AstAlgorithm {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(Ui(SelectDiffAlgorithm(AstAlgorithm))),
        "AST",
      ),
    ],
  )
}

///|
fn ignore_comments_control(
  ignore_comments : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class=if ignore_comments {
      "toolbar-button ignore-comments-toggle active"
    } else {
      "toolbar-button ignore-comments-toggle"
    },
    title=if ignore_comments {
      "Show comment and blank-line changes"
    } else {
      "Ignore MoonBit comment and blank-line changes"
    },
    attrs=@html.Attrs::build()
      .aria_label("Ignore comments")
      .aria_pressed(if ignore_comments { "true" } else { "false" }),
    on_click=emit(Ui(ToggleIgnoreComments)),
    [
      @html.span(class="ignore-comments-icon", "//"),
      @html.span(class="ignore-comments-label", "Ignore comments"),
    ],
  )
}

///|
fn ignore_tests_control(
  ignore_tests : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class=if ignore_tests {
      "toolbar-button ignore-tests-toggle active"
    } else {
      "toolbar-button ignore-tests-toggle"
    },
    title=if ignore_tests {
      "Show MoonBit test changes"
    } else {
      "Ignore top-level MoonBit test and async test blocks"
    },
    attrs=@html.Attrs::build()
      .aria_label("Ignore tests")
      .aria_pressed(if ignore_tests { "true" } else { "false" }),
    on_click=emit(Ui(ToggleIgnoreTests)),
    [
      @html.span(class="ignore-tests-icon", "T"),
      @html.span(class="ignore-tests-label", "Ignore tests"),
    ],
  )
}

///|
fn workspace_actions(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  match model.phase {
    Showing(commit) => {
      let view_label = match model.view_mode {
        Split => "Use unified view"
        Unified => "Use split view"
      }
      let source_label = match commit.reference.target {
        Commit(_) => "Open commit on GitHub"
        PullRequest(_) => "Open pull request on GitHub"
        PullCommit(_, _) => "Open pull request commit on GitHub"
      }
      @html.nav(
        class="workspace-actions",
        attrs=@html.Attrs::build().aria_label("Diff actions"),
        [
          @html.a(
            href=commit.html_url,
            target=Blank,
            rel="noopener noreferrer",
            class="toolbar-button source-button",
            title=source_label,
            attrs=@html.Attrs::build().aria_label(source_label),
            @html.span(class="source-icon", "↗"),
          ),
          algorithm_control(model.diff_algorithm, emit),
          ignore_comments_control(model.ignore_comments, emit),
          ignore_tests_control(model.ignore_tests, emit),
          @html.span(class="toolbar-divider", ""),
          @html.button(
            type_="button",
            class=match model.view_mode {
              Split => "toolbar-button view-toggle view-split"
              Unified => "toolbar-button view-toggle view-unified"
            },
            title=view_label,
            attrs=@html.Attrs::build().aria_label(view_label),
            on_click=emit(Ui(ToggleView)),
            @html.span(class="view-icon", ""),
          ),
          share_control(model, emit),
        ],
      )
    }
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
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
  whole : Bool,
  show_hunk_headers? : Bool = true,
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
      @html.summary(class="semantic-section-title", title)
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
      )
    },
  ]
  if whole {
    @html.section(class="semantic-whole", content)
  } else {
    @html.details(class="semantic-section", open=true, content)
  }
}

///|
fn top_level_diff_view(
  file : ApiFile,
  file_index : Int,
  top : @mbtdiff.TopLevelDiff,
  mode : ViewMode,
  show_hunk_headers : Bool,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let sections : Array[@rabbita.Html] = []
  if top.reordered {
    sections.push(
      @html.div(
        class="semantic-reorder",
        "Top-level declarations are reordered; fragment diffs remain paired by declaration identity.",
      ),
    )
  }
  for section_index in top.new_order {
    guard top.sections.get(section_index) is Some(section) else { continue }
    if section is Deleted(..) {
      continue
    }
    let fragment = semantic_section_fragment(section)
    if fragment_has_output(fragment) {
      sections.push(
        semantic_fragment_view(
          file,
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
          show_hunk_headers~,
        ),
      )
    }
  }

  let deleted : Array[@rabbita.Html] = []
  for section_index in top.old_order {
    guard top.sections.get(section_index) is Some(section) else { continue }
    if section is Deleted(..) {
      let fragment = semantic_section_fragment(section)
      if fragment_has_output(fragment) {
        deleted.push(
          semantic_fragment_view(
            file,
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
            show_hunk_headers~,
          ),
        )
      }
    }
  }
  if !deleted.is_empty() {
    sections.push(
      @html.section(class="semantic-deleted-group", [
        @html.h4("Deleted declarations (old order)"),
        @html.fragment(deleted),
      ]),
    )
  }
  @html.div(class="semantic-document", sections)
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
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
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
          safe_review_diff(file.file, index, document, mode, review, emit)
        MoonBit(document~, status~) => {
          if status is IgnoredOnly {
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
            return @html.div(class="file-message structural-empty", [
              @html.p(
                "No structural changes found. Switch to Lexical to view text changes.",
              ),
            ])
          }
          match document {
            Whole(fragment) =>
              semantic_fragment_view(
                file.file,
                index,
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
              )
            TopLevel(top) =>
              top_level_diff_view(
                file.file,
                index,
                top,
                mode,
                algorithm is AstAlgorithm,
                review,
                emit,
              )
          }
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
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let toggle_label = if file.expanded { "Collapse" } else { "Expand" }
  @html.article(
    id=file_dom_id(index),
    class=if file.expanded { "file-card expanded" } else { "file-card" },
    [
      @html.div(class="file-heading", [
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
        @html.div(class="file-actions", [
          @html.span(class="status-label", status_label(file.file.status)),
          @html.span(class="file-stats", [
            @html.span(class="additions", "+\{file.file.additions}"),
            @html.span(class="deletions", "−\{file.file.deletions}"),
          ]),
        ]),
      ]),
      if file.expanded {
        file_diff_view(
          file, generation, index, mode, algorithm, ignore_comments, ignore_tests,
          review, emit,
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
  let file_views : Array[@rabbita.Html] = []
  for index, file in commit.files {
    file_views.push(
      file_card(
        file,
        model.generation,
        index,
        model.view_mode,
        model.diff_algorithm,
        model.ignore_comments,
        model.ignore_tests,
        model.review,
        emit,
      ),
    )
    file_views.push(file_discussions_view(commit, index, model.review, emit))
  }
  @html.div(class="file-list", file_views)
}

///|
fn change_view(
  commit : ChangeView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let section_label = match
    (extension_host_enabled(), commit.reference.target) {
    (true, Commit(_)) => "GitHub commit"
    (true, PullRequest(_)) => "GitHub pull request"
    (true, PullCommit(_, _)) => "GitHub pull request commit"
    (false, Commit(_)) => "Public commit"
    (false, PullRequest(_)) => "Public pull request"
    (false, PullCommit(_, _)) => "Public pull request commit"
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
    comments_overview(commit, model.review, emit),
    file_list_view(commit, model, emit),
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
        if extension_host_enabled() {
          auth_controls(model.review, emit)
        } else {
          @html.nothing
        },
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
