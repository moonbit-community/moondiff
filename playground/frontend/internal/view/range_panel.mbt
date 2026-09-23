///|
fn range_short_sha(sha : String) -> String {
  sha.view(start_offset=0, end_offset=Int::min(7, sha.length())).to_owned()
}

///|
fn range_commit_title(message : String) -> String {
  message.split("\n").next().unwrap_or("").to_owned()
}

///|
fn range_from_options(state : @application.RangeState) -> Array[@rabbita.Html] {
  let options : Array[@rabbita.Html] = []
  if state.commits.is_empty() &&
    state.next_page is Some(_) &&
    @application.range_commit_after(state, state.base_sha, state.to_sha) {
    options.push(
      @html.option(
        value=state.base_sha,
        selected=state.from_sha == state.base_sha,
        "PR start · first included commit",
      ),
    )
  }
  let mut previous = state.base_sha
  let commits = state.linear_commits.unwrap_or(state.commits)
  for commit in commits {
    if commit.sha != state.base_sha {
      if @application.range_commit_after(state, previous, state.to_sha) {
        let title = range_commit_title(commit.commit.message)
        options.push(
          @html.option(
            value=previous,
            selected=state.from_sha == previous,
            "\{range_short_sha(commit.sha)} · \{title}",
          ),
        )
      }
      previous = commit.sha
    }
  }
  options
}

///|
fn range_to_options(state : @application.RangeState) -> Array[@rabbita.Html] {
  let options : Array[@rabbita.Html] = []
  let commits = state.linear_commits.unwrap_or(state.commits)
  for commit in commits {
    if @application.range_commit_after(state, state.from_sha, commit.sha) {
      let title = range_commit_title(commit.commit.message)
      options.push(
        @html.option(
          value=commit.sha,
          selected=state.to_sha == commit.sha,
          "\{range_short_sha(commit.sha)} · \{title}",
        ),
      )
    }
  }
  if !commits.iter().any(commit => commit.sha == state.head_sha) &&
    @application.range_commit_after(state, state.from_sha, state.head_sha) {
    options.push(
      @html.option(
        value=state.head_sha,
        selected=state.to_sha == state.head_sha,
        "\{range_short_sha(state.head_sha)} · PR head",
      ),
    )
  }
  options
}

///|
fn range_manual_reason(state : @application.RangeState) -> String? {
  guard state.next_page is Some(_) && state.pull is Some(pull) else {
    return None
  }
  match pull.commits {
    Some(count) if count > 250 =>
      Some(
        "This PR has \{count} commits. GitHub lists at most 250 PR commits, so load commit choices from the comparison when needed.",
      )
    None if state.total_commits > 250 =>
      Some(
        "This comparison has \{state.total_commits} commits. GitHub lists at most 250 PR commits, so load more commit choices when needed.",
      )
    _ => None
  }
}

///|
fn range_more_control(
  state : @application.RangeState,
  emit : @rabbita.Emit[Msg],
  selector? : Bool = false,
) -> @rabbita.Html {
  let reason = if selector { range_manual_reason(state) } else { None }
  @html.fragment([
    if reason is Some(message) {
      @html.p(class="range-manual-reason", message)
    } else {
      @html.nothing
    },
    if state.loading_page is Some(_) {
      @html.span(class="range-loading", "Loading commits…")
    } else {
      @html.nothing
    },
    if state.next_page is Some(_) &&
      state.loading_page is None &&
      (!selector || reason is Some(_) || state.error is Some(_)) {
      @html.button(
        type_="button",
        class="secondary range-load-more",
        on_click=emit(@application.Msg::Range(LoadMore)),
        if state.error is Some(_) {
          "Retry loading commits"
        } else if state.commits.is_empty() {
          "Load PR commits"
        } else {
          "Load more commits"
        },
      )
    } else {
      @html.nothing
    },
    if state.error is Some(error) {
      @html.p(class="range-error", error)
    } else {
      @html.nothing
    },
  ])
}

///|
fn pull_range_selector(
  input : RangePanelInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let state = input.state
  let selector_ready = @application.range_pull_selector_ready(state)
  guard input.reference.target is PullRequest(number) else {
    return @html.nothing
  }
  let can_view = selector_ready &&
    @application.range_commit_after(state, state.from_sha, state.to_sha) &&
    @github.valid_sha(state.from_sha) &&
    @github.valid_sha(state.to_sha)
  @html.section(class="range-panel range-selector", [
    @html.div(class="range-panel-heading", [
      @html.div([
        @html.p(class="section-label", "Commit interval"),
        @html.h3("Review commit interval of this PR"),
      ]),
    ]),
    if state.pull
      .map(pull => pull.changed_files > @github.MAX_PULL_FILES)
      .unwrap_or(false) {
      @html.p(class="range-limit", @github.PULL_FILE_LIMIT_ERROR)
    } else {
      @html.nothing
    },
    @html.div(class="range-selector-form", [
      @html.label(class="range-field", [
        @html.span("From"),
        @html.select(
          disabled=!selector_ready,
          on_change=value => emit(@application.Msg::Range(FromSelected(value))),
          range_from_options(state),
        ),
      ]),
      @html.label(class="range-field", [
        @html.span("To"),
        @html.select(
          disabled=!selector_ready,
          on_change=value => emit(@application.Msg::Range(ToSelected(value))),
          range_to_options(state),
        ),
      ]),
      if can_view {
        let target = @github.pull_range_reference(
          input.reference.owner,
          input.reference.repo,
          number,
          state.from_sha,
          state.to_sha,
        )
        @html.a(
          href=@routing.playground_route(target),
          target=Blank,
          rel="noopener noreferrer",
          class="secondary range-apply",
          "View interval",
        )
      } else {
        @html.button(
          type_="button",
          class="secondary range-apply",
          disabled=true,
          "View interval",
        )
      },
    ]),
    if @application.range_pull_history_unsupported(state) {
      @html.p(
        class="range-limit range-unsupported",
        "This PR has a branched or merged commit history. Commit intervals are available only for a single unmerged commit chain.",
      )
    } else {
      @html.nothing
    },
    range_more_control(state, emit, selector=true),
  ])
}

///|
fn range_review_panel(
  input : RangePanelInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let state = input.state
  let reference = input.reference
  let first_title = if state.commits.is_empty() {
    range_commit_title(state.comparison.unwrap().base_commit.commit.message)
  } else {
    range_commit_title(state.commits[0].commit.message)
  }
  let head_title = match state.commits.last() {
    Some(commit) => range_commit_title(commit.commit.message)
    None => first_title
  }
  let github_url = "https://github.com/\{reference.owner}/\{reference.repo}/compare/\{state.base_sha}...\{state.head_sha}"
  let count = if state.too_many_files {
    "300 or more"
  } else {
    input.file_count.to_string()
  }
  let commit_noun = if state.total_commits == 1 { "commit" } else { "commits" }
  let file_noun = if !state.too_many_files && input.file_count == 1 {
    "file"
  } else {
    "files"
  }
  let commit_link = if state.total_commits == 1 {
    match reference.target {
      PullRange(number, _, _) =>
        Some(
          "/\{reference.owner}/\{reference.repo}/pull/\{number}/commits/\{state.head_sha}",
        )
      _ =>
        Some("/\{reference.owner}/\{reference.repo}/commit/\{state.head_sha}")
    }
  } else {
    None
  }
  @html.section(class="range-panel range-review", [
    @html.div(class="range-panel-heading", [
      @html.div([
        @html.p(class="section-label", "Commit interval"),
        @html.h3(class="range-review-title", [
          @html.span(class="range-title-commit", first_title),
          @html.span(class="range-title-separator", " .. "),
          @html.span(class="range-title-commit", head_title),
        ]),
      ]),
      @html.button(
        type_="button",
        class="secondary range-copy",
        on_click=emit(@application.Msg::Range(CopyLink)),
        "Copy link",
      ),
    ]),
    @html.p(
      class="range-summary",
      if state.too_many_files {
        "\{state.total_commits} \{commit_noun} · \{count} \{file_noun}"
      } else {
        "\{state.total_commits} \{commit_noun} · \{count} \{file_noun} · +\{input.stats.additions} −\{input.stats.deletions}"
      },
    ),
    if state.too_many_files {
      @html.p(class="range-limit", [
        @html.span(
          "GitHub compare lists at most 300 changed files. This interval may be incomplete, so its diff cannot be reviewed here. ",
        ),
        @html.a(
          href=github_url,
          target=Blank,
          rel="noopener noreferrer",
          "Open on GitHub ↗",
        ),
      ])
    } else {
      @html.nothing
    },
    if commit_link is Some(url) {
      @html.div(class="range-links", [
        @html.a(href="\{url}#comments", "Go to commit comments"),
      ])
    } else {
      @html.nothing
    },
    @html.button(
      type_="button",
      class="secondary range-toggle-commits",
      attrs=@html.Attrs::build().aria_expanded(
        if state.expanded {
          "true"
        } else {
          "false"
        },
      ),
      on_click=emit(@application.Msg::Range(ToggleCommits)),
      if state.expanded {
        "Hide commits"
      } else {
        "Show commits"
      },
    ),
    if state.expanded {
      @html.div(class="range-commits", [
        @html.ol(
          state.commits.map(commit => {
            @html.li([
              @html.code(range_short_sha(commit.sha)),
              @html.span(range_commit_title(commit.commit.message)),
            ])
          }),
        ),
        range_more_control(state, emit),
      ])
    } else {
      @html.nothing
    },
  ])
}

///|
fn range_panel_view(
  input : RangePanelInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if input.reference.target is PullRequest(_) {
    pull_range_selector(input, emit)
  } else {
    range_review_panel(input, emit)
  }
}
