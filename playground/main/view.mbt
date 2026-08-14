// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

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
    @html.label(for_="commit-url", class="sr-only", "Public GitHub commit URL"),
    @html.div(class="input-row", [
      @html.input(
        id="commit-url",
        input_type=Url,
        value=model.input,
        placeholder="https://github.com/owner/repo/commit/sha",
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
      @html.span(".com/owner/repo/commit/sha"),
    ]),
    @html.code(class="route-new", [
      @html.span(class="route-prefix", "+ playground"),
      @html.span("/#/owner/repo/commit/sha"),
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
          @html.code("github.com/owner/repo/commit/sha"),
        ]),
        @html.li([
          @html.span(class="list-arrow", "→"),
          @html.code("github.com/owner/repo/pull/number/changes/sha"),
        ]),
      ]),
      @html.p(
        "Opening the generated playground URL restores the same commit automatically.",
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
          "Review text changes from a public GitHub commit and share the exact playground URL with anyone.",
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
      "Show comment changes"
    } else {
      "Ignore MoonBit comment changes"
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
fn workspace_actions(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  match model.phase {
    Showing(commit) => {
      let view_label = match model.view_mode {
        Split => "Use unified view"
        Unified => "Use split view"
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
            title="Open commit on GitHub",
            attrs=@html.Attrs::build().aria_label("Open commit on GitHub"),
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
fn diff_notice(outcome : @alignment.AlignedDiffOutcome) -> DiffNotice? {
  match outcome {
    @alignment.AlignedDiffOutcome::Fallback(reason) =>
      Some({
        class_name: "diff-notice fallback",
        label: "Lexical fallback",
        message: "AST diff was unavailable, so this entire file is shown using lexical diff. \{reason}",
      })
    @alignment.AlignedDiffOutcome::PartialFallback(reasons) =>
      Some({
        class_name: "diff-notice partial-fallback",
        label: "Partial lexical fallback",
        message: "AST diff was used for the rest of this file. Lexical diff was used only for: \{reasons.join("; ")}.",
      })
    _ => None
  }
}

///|
#warnings("-alert_xss_vulnerable")
fn file_diff_view(
  file : FileState,
  generation : Int,
  index : Int,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
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
      guard cached_file_document(file, algorithm, ignore_comments~)
        is Some(result) else {
        return @html.p(class="file-message loading-inline", "Preparing diff…")
      }
      if result.outcome is @alignment.AlignedDiffOutcome::NoNonCommentChanges {
        return @html.div(class="file-message comment-empty", [
          @html.p(
            if algorithm is AstAlgorithm {
              "No structural non-comment changes found. Turn off Ignore comments to view comment changes."
            } else {
              "No non-comment changes found. Turn off Ignore comments to view comment changes."
            },
          ),
        ])
      }
      if result.outcome is @alignment.AlignedDiffOutcome::NoStructuralChanges {
        return @html.div(class="file-message structural-empty", [
          @html.p(
            "No structural changes found. Switch to Lexical to view text changes.",
          ),
        ])
      }
      let rendered = match mode {
        Split =>
          @tokdiff_html.render_side_by_side(result.document, line_numbers=true)
        Unified =>
          @tokdiff_html.render_unified(result.document, line_numbers=true)
      }
      // `rendered` is the only raw HTML accepted by the application. tokdiff
      // has already escaped every source line and hunk header.
      @html.fragment([
        match diff_notice(result.outcome) {
          Some(notice) =>
            @html.div(class=notice.class_name, [
              @html.strong(notice.label),
              @html.span(notice.message),
            ])
          None => @html.nothing
        },
        @html.div(
          class="diff-scroll",
          attrs=@html.Attrs::build().inner_html(rendered),
          ([] : Array[@rabbita.Html]),
        ),
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
          file, generation, index, mode, algorithm, ignore_comments, emit,
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn file_list_view(
  commit : CommitView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if commit.files.length() == 0 {
    return @html.div(
      class="empty-state",
      "No changed files were returned for this commit.",
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
        emit,
      ),
    )
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
) -> Array[String] {
  guard cached_file_document(file, algorithm, ignore_comments~) is Some(diff) else {
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
  commit : CommitView,
  result : AnalysisResult,
  expanded : ArrayView[Bool],
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
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
      file, file_index, result, mode, algorithm, ignore_comments,
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
  commit : CommitView,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
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
          @html.p("OpenSeek is grouping the commit's hunks by function."),
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
        commit, result, expanded, mode, algorithm, ignore_comments,
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
fn commit_view(
  commit : CommitView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.section(class="results", [
    @html.div(class="commit-card", [
      @html.div(class="commit-title", [
        @html.div(class="commit-identity", [
          @html.p(class="section-label", "Public commit"),
          @html.a(
            href=commit.html_url,
            target=Blank,
            rel="noopener noreferrer",
            "\{commit.reference.owner}/\{commit.reference.repo}@\{commit.sha}",
          ),
          @html.p(
            class="parent",
            if commit.parent_sha is Some(parent) {
              "Compared with first parent \{parent}."
            } else {
              "Root commit; compared with an empty tree."
            },
          ),
        ]),
        @html.pre(class="commit-message", commit.message),
      ]),
    ]),
    analysis_overview(
      commit,
      model.view_mode,
      model.diff_algorithm,
      model.ignore_comments,
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
    LoadFailed(message) =>
      @html.div(class="empty-state error", [
        @html.p(message),
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Submit),
          "Try again",
        ),
      ])
    Showing(commit) => commit_view(commit, model, emit)
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
