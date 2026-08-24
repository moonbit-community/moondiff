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
  @html.form(on_submit=emit(Submit), class="commit-form", [
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
        on_input=value => emit(InputChanged(value)),
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
        on_click=emit(CopyShareLink),
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
        on_click=emit(SelectDiffAlgorithm(LexicalAlgorithm)),
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
        on_click=emit(SelectDiffAlgorithm(AstAlgorithm)),
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
    on_click=emit(ToggleIgnoreComments),
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
    on_click=emit(ToggleIgnoreTests),
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
          if model.backend_status is BackendReady {
            let (label, busy) = match model.analysis_status {
              PreparingSources => ("Preparing source…", true)
              Analyzing => ("Analyzing…", true)
              AnalysisDone(_, _, _) | AnalysisNoHunks(_) =>
                ("Analyze again", false)
              AnalysisFailed(_) => ("Retry analysis", false)
              AnalysisIdle => ("Analyze changes", false)
            }
            @html.button(
              type_="button",
              class="toolbar-button analyze-button",
              title=label,
              disabled=busy,
              attrs=@html.Attrs::build().aria_label(label),
              on_click=emit(AnalyzeChanges),
              [
                @html.span(class="analyze-icon", "✦"),
                @html.span(class="analyze-label", label),
              ],
            )
          } else {
            @html.nothing
          },
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
            on_click=emit(ToggleView),
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
priv struct DiffNotice {
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
fn fallback_location(scope : @mbtdiff.FallbackScope) -> String {
  match scope {
    WholeFile => ""
    Region(old~, new~) => {
      let parts : Array[String] = []
      if old is Some(range) {
        parts.push("old line \{range.start + 1}")
      }
      if new is Some(range) {
        parts.push("new line \{range.start + 1}")
      }
      if parts.is_empty() {
        "file"
      } else {
        parts.join(", ")
      }
    }
  }
}

///|
fn fallback_reason_text(fallback : @mbtdiff.FallbackInfo) -> String {
  match fallback.reason {
    ParseError(detail~, ..) => detail
    GraphLimitExceeded(limit~) => {
      let base = "graph limit exceeded (\{limit})"
      let location = fallback_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
    ComputationLimitExceeded(stage~, limit~) => {
      let base = "computation limit exceeded (\{limit}) during \{fallback_stage_text(stage)}"
      let location = fallback_location(fallback.scope)
      if location.is_empty() {
        base
      } else {
        "\{base} at \{location}"
      }
    }
    TopLevelReordering =>
      "top-level reordering has no changes inside aligned declarations"
  }
}

///|
fn diff_notice(fallbacks : ArrayView[@mbtdiff.FallbackInfo]) -> DiffNotice? {
  if fallbacks.is_empty() {
    return None
  }
  if fallbacks is [fallback] && fallback.scope is WholeFile {
    let reason = fallback_reason_text(fallback)
    return Some({
      class_name: "diff-notice fallback",
      label: "Lexical fallback",
      message: "AST diff was unavailable, so this entire file is shown using lexical diff. \{reason}",
    })
  }
  let reasons = fallbacks.map(fallback_reason_text)
  Some({
    class_name: "diff-notice partial-fallback",
    label: "Partial lexical fallback",
    message: "AST diff was used for the rest of this file. Lexical diff was used only for: \{reasons.join("; ")}.",
  })
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
          on_click=emit(RetryFile(generation, index)),
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
      if result.status is IgnoredOnly {
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
        result.status is (Identical | NoStructuralChanges) {
        return @html.div(class="file-message structural-empty", [
          @html.p(
            "No structural changes found. Switch to Lexical to view text changes.",
          ),
        ])
      }
      @html.fragment([
        if diff_notice(result.fallbacks) is Some(notice) {
          @html.div(class=notice.class_name, [
            @html.strong(notice.label),
            @html.span(notice.message),
          ])
        } else {
          @html.nothing
        },
        safe_review_diff(file.file, index, result.document, mode, review, emit),
      ])
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
          on_click=emit(ToggleFile(generation, index)),
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
priv struct RenderedAnalysisHunk {
  file : FileState
  html : String
}

///|
fn analysis_hunk_count(hunks : ArrayView[AnalyzedHunk]) -> String {
  if hunks.length() == 1 {
    "1 hunk"
  } else {
    "\{hunks.length()} hunks"
  }
}

///|
fn analysis_file_hunks_html(
  file : FileState,
  file_index : Int,
  result : AnalysisResult,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
) -> Array[String] {
  guard cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(diff) else {
    return []
  }
  let hunk_notes = notes_for_file(
    result,
    file_index,
    diff.document.hunks.length(),
  )
  match mode {
    Split =>
      @tokdiff_html.render_side_by_side_hunks(
        diff.document,
        line_numbers=true,
        hunk_notes~,
      )
    Unified =>
      @tokdiff_html.render_unified_hunks(
        diff.document,
        line_numbers=true,
        hunk_notes~,
      )
  }
}

///|
fn analysis_wants_file(wanted : Map[String, Unit], file_index : Int) -> Bool {
  let prefix = "f\{file_index}-h"
  for id, _ in wanted {
    if id.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
fn rendered_analysis_hunks(
  commit : ChangeView,
  result : AnalysisResult,
  expanded : ArrayView[Bool],
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
) -> Map[String, RenderedAnalysisHunk] {
  let wanted : Map[String, Unit] = Map([])
  for group_index, group in result.groups {
    if expanded.get(group_index) == Some(true) {
      for hunk in group.hunks {
        wanted[hunk.id] = ()
      }
    }
  }
  let rendered : Map[String, RenderedAnalysisHunk] = Map([])
  for file_index, file in commit.files {
    if !analysis_wants_file(wanted, file_index) {
      continue
    }
    let hunks = analysis_file_hunks_html(
      file, file_index, result, mode, algorithm, ignore_comments, ignore_tests,
    )
    for hunk_index, html in hunks {
      let id = "f\{file_index}-h\{hunk_index}"
      if wanted.contains(id) {
        rendered[id] = { file, html }
      }
    }
  }
  rendered
}

///|
#warnings("-alert_xss_vulnerable")
fn analysis_hunk_view(
  hunk : AnalyzedHunk,
  rendered : Map[String, RenderedAnalysisHunk],
) -> @rabbita.Html {
  if rendered.get(hunk.id) is Some(item) {
    @html.article(class="analysis-hunk", [
      @html.div(class="analysis-hunk-heading", [
        @html.div(class="analysis-hunk-file", [
          @html.span(class=status_class(item.file.file.status), ""),
          @html.code(class="file-path", file_label(item.file.file)),
        ]),
        @html.span(class="status-label", status_label(item.file.file.status)),
      ]),
      // tokdiff escapes source text, hunk headers, group titles, and hunk
      // explanations before this raw HTML reaches the application.
      @html.div(
        class="diff-scroll",
        attrs=@html.Attrs::build().inner_html(item.html),
        ([] : Array[@rabbita.Html]),
      ),
    ])
  } else {
    @html.article(class="analysis-hunk analysis-hunk-error", [
      @html.p(
        "The analysis referenced \{hunk.id}, but that diff hunk could not be rendered.",
      ),
    ])
  }
}

///|
fn analysis_group_view(
  group : AnalysisGroup,
  group_index : Int,
  expanded : Bool,
  rendered : Map[String, RenderedAnalysisHunk],
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let hunk_views : Array[@rabbita.Html] = []
  if expanded {
    for hunk in group.hunks {
      hunk_views.push(analysis_hunk_view(hunk, rendered))
    }
  }
  let action = if expanded { "Collapse" } else { "Expand" }
  @html.article(
    class=if expanded { "analysis-group expanded" } else { "analysis-group" },
    [
      @html.button(
        type_="button",
        class="analysis-group-toggle",
        attrs=@html.Attrs::build()
          .aria_expanded(if expanded { "true" } else { "false" })
          .aria_label("\{action} \{group.title}"),
        on_click=emit(ToggleAnalysisGroup(group_index)),
        [
          @html.span(class="analysis-group-disclosure", ""),
          @html.span(class="analysis-group-title", group.title),
          @html.span(
            class="analysis-hunk-count",
            analysis_hunk_count(group.hunks),
          ),
        ],
      ),
      @html.p(group.description),
      if expanded {
        @html.div(class="analysis-hunks", hunk_views)
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn analysis_skipped_view(skipped : ArrayView[SkippedFile]) -> @rabbita.Html {
  if skipped.is_empty() {
    return @html.nothing
  }
  let skipped_views : Array[@rabbita.Html] = []
  for file in skipped {
    skipped_views.push(
      @html.li([@html.code(file.path), @html.span(" — \{file.reason}")]),
    )
  }
  @html.div(class="analysis-skipped", [
    @html.p(
      "Skipped \{skipped.length()} \{if skipped.length() == 1 { "file" } else { "files" }}:",
    ),
    @html.ul(skipped_views),
  ])
}

///|
fn analysis_overview(
  commit : ChangeView,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  status : AnalysisStatus,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match status {
    AnalysisIdle => @html.nothing
    PreparingSources =>
      @html.section(class="analysis-card analysis-progress", [
        @html.span(class="spinner", ""),
        @html.div([
          @html.h2("Preparing source files"),
          @html.p(
            "Loading both sides of every changed file before analysis. File cards stay as you left them.",
          ),
        ]),
      ])
    Analyzing =>
      @html.section(class="analysis-card analysis-progress", [
        @html.span(class="spinner", ""),
        @html.div([
          @html.h2("Analyzing changes"),
          @html.p("OpenSeek is grouping the loaded diff hunks by function."),
        ]),
      ])
    AnalysisFailed(message) =>
      @html.section(class="analysis-card analysis-error", [
        @html.div([@html.h2("Analysis failed"), @html.p(message)]),
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(AnalyzeChanges),
          "Retry analysis",
        ),
      ])
    AnalysisNoHunks(skipped) =>
      @html.section(class="analysis-card analysis-complete", [
        @html.p(class="section-label", "OpenSeek functional analysis"),
        @html.h2("Nothing to analyze"),
        @html.p(
          class="analysis-empty",
          "No diff hunks are available for the current algorithm, so no backend request was sent.",
        ),
        analysis_skipped_view(skipped),
      ])
    AnalysisDone(result, skipped, expanded) => {
      let rendered = rendered_analysis_hunks(
        commit, result, expanded, mode, algorithm, ignore_comments, ignore_tests,
      )
      let group_views : Array[@rabbita.Html] = []
      for group_index, group in result.groups {
        group_views.push(
          analysis_group_view(
            group,
            group_index,
            expanded.get(group_index).unwrap_or(false),
            rendered,
            emit,
          ),
        )
      }
      @html.section(class="analysis-card analysis-complete", [
        @html.p(class="section-label", "OpenSeek functional analysis"),
        @html.h2("Change groups"),
        @html.p(class="analysis-summary", result.summary),
        analysis_skipped_view(skipped),
        if group_views.length() == 0 {
          @html.p(
            class="analysis-empty",
            "No text diff hunks were available to group.",
          )
        } else {
          @html.div(class="analysis-groups", group_views)
        },
      ])
    }
  }
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
    analysis_overview(
      commit,
      model.view_mode,
      model.diff_algorithm,
      model.ignore_comments,
      model.ignore_tests,
      model.analysis_status,
      emit,
    ),
    match model.analysis_status {
      AnalysisDone(_, _, _) => @html.nothing
      _ => file_list_view(commit, model, emit)
    },
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
          on_click=emit(Submit),
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
fn app_view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
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
