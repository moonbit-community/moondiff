///|
fn ci_state_icon(state : @protocol.ApiCiState) -> String {
  match state {
    Success => "✓"
    Pending => "●"
    Failure => "×"
    Neutral => "○"
  }
}

///|
fn ci_state_name(state : @protocol.ApiCiState) -> String {
  match state {
    Success => "Successful"
    Pending => "In progress"
    Failure => "Failing"
    Neutral => "Neutral"
  }
}

///|
fn ci_state_class(state : @protocol.ApiCiState) -> String {
  match state {
    Success => "success"
    Pending => "pending"
    Failure => "failure"
    Neutral => "neutral"
  }
}

///|
fn ci_summary_text(status : @protocol.ApiPullMergeStatus) -> String {
  match status.ci_summary {
    Some(Success) => "All checks have passed"
    Some(Pending) => "Some checks haven’t completed yet"
    Some(Failure) => "Some checks were not successful"
    Some(Neutral) => "Checks completed with neutral results"
    None => "No checks were run"
  }
}

///|
fn ci_summary_icon(status : @protocol.ApiPullMergeStatus) -> String {
  status.ci_summary.map(ci_state_icon).unwrap_or("○")
}

///|
fn ci_checks_count_text(checks : ArrayView[@protocol.ApiCiCheck]) -> String {
  if checks.is_empty() {
    return "No checks were run"
  }
  let counts = [0, 0, 0, 0]
  for check in checks {
    match check.state {
      Failure => counts[0] += 1
      Pending => counts[1] += 1
      Success => counts[2] += 1
      Neutral => counts[3] += 1
    }
  }
  let labels : Array[String] = []
  if counts[0] > 0 {
    labels.push("\{counts[0]} failing")
  }
  if counts[1] > 0 {
    labels.push("\{counts[1]} in progress")
  }
  if counts[2] > 0 {
    labels.push("\{counts[2]} successful")
  }
  if counts[3] > 0 {
    labels.push("\{counts[3]} neutral")
  }
  "\{labels.join(" and ")} \{if checks.length() == 1 { "check" } else { "checks" }}"
}

///|
fn ci_check_status_text(check : @protocol.ApiCiCheck) -> String {
  let state = ci_state_name(check.state)
  let generic = match check.description.to_lower() {
    "success"
    | "failure"
    | "timed_out"
    | "cancelled"
    | "action_required"
    | "startup_failure"
    | "neutral"
    | "skipped"
    | "stale"
    | "queued"
    | "in_progress"
    | "completed"
    | "pending"
    | "error" => true
    _ => false
  }
  if check.description.is_empty() || generic {
    state
  } else {
    "\{state} — \{check.description}"
  }
}

///|
fn ci_details_view(status : @protocol.ApiPullMergeStatus) -> @rabbita.Html {
  let items : Array[@rabbita.Html] = []
  for check in status.ci_checks {
    let details_url = check.details_url.filter(url => {
      url.has_prefix("https://") || url.has_prefix("http://")
    })
    let row = [
      @html.span(
        class="pull-ci-icon",
        attrs=@html.Attrs::build().aria_hidden("true"),
        ci_state_icon(check.state),
      ),
      @html.div(class="pull-ci-copy", [
        @html.strong(class="pull-ci-name", check.name),
        @html.span(class="pull-ci-state", ci_check_status_text(check)),
      ]),
      if details_url is Some(_) {
        @html.span(class="pull-ci-details", "Details")
      } else {
        @html.nothing
      },
    ]
    items.push(
      @html.li(
        class="pull-ci-check ci-\{ci_state_class(check.state)}",
        match details_url {
          Some(url) =>
            @html.a(
              class="pull-ci-check-row",
              href=url,
              target=Blank,
              rel="noopener noreferrer",
              attrs=@html.Attrs::build().aria_label("View \{check.name} CI job"),
              row,
            )
          _ => @html.div(class="pull-ci-check-row", row)
        },
      ),
    )
  }
  @html.ul(class="pull-ci-list", items)
}

///|
fn ci_warning_view(status : @protocol.ApiPullMergeStatus) -> @rabbita.Html {
  if status.ci_warnings.is_empty() {
    return @html.nothing
  }
  @html.div(class="pull-ci-warning", [
    @html.strong("CI results are incomplete."),
    @html.ul(status.ci_warnings.map(message => @html.li(message))),
  ])
}

///|
fn ci_status_view(status : @protocol.ApiPullMergeStatus) -> @rabbita.Html {
  let summary_class = status.ci_summary.map(ci_state_class).unwrap_or("neutral")
  let summary = [
    @html.span(
      class="pull-ci-icon",
      attrs=@html.Attrs::build().aria_hidden("true"),
      ci_summary_icon(status),
    ),
    @html.span(class="pull-ci-summary-copy", [
      @html.strong(ci_summary_text(status)),
      if status.ci_checks.is_empty() {
        @html.nothing
      } else {
        @html.span(
          class="pull-ci-count",
          ci_checks_count_text(status.ci_checks),
        )
      },
    ]),
  ]
  if status.ci_checks.is_empty() {
    return @html.fragment([
      @html.div(
        class="pull-ci-summary pull-ci-summary-empty ci-\{summary_class}",
        summary,
      ),
      ci_warning_view(status),
    ])
  }
  @html.fragment([
    @html.details(class="pull-ci-disclosure", [
      @html.summary(
        class="pull-ci-summary ci-\{summary_class}",
        [
          ..summary,
          @html.span(class="pull-ci-toggle", [
            @html.span(class="pull-ci-show-label", "Show all checks"),
            @html.span(class="pull-ci-hide-label", "Hide all checks"),
            @html.span(
              class="pull-ci-chevron",
              attrs=@html.Attrs::build().aria_hidden("true"),
              "⌄",
            ),
          ]),
        ],
      ),
      ci_details_view(status),
    ]),
    ci_warning_view(status),
  ])
}

///|
fn pull_merge_action_view(
  input : PullMergeInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let stale = input.state.stale || input.snapshot_stale
  if stale {
    return @html.div(class="pull-merge-action-state", [
      @html.p(
        "This PR snapshot is out of date. Load the latest changes before merging.",
      ),
      @html.button(
        type_="button",
        class="secondary load-latest-snapshot",
        attrs=@html.Attrs::build().aria_label("Reload PR for merge"),
        on_click=emit(Review(LoadLatestSnapshot)),
        "Load latest",
      ),
    ])
  }
  if !(input.auth is SignedIn(..)) {
    return @html.div(class="pull-merge-action-state", [
      @html.p(
        "Sign in with GitHub to view checks and rebase-merge this pull request.",
      ),
      if input.auth is (Anonymous(_) | AuthFailed(_)) {
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Auth(StartSignIn)),
          "Sign in to merge",
        )
      } else {
        @html.nothing
      },
    ])
  }
  guard input.state.status is Some(status) else {
    return @html.p(
      class="pull-merge-action-state",
      if input.state.loading {
        "Checking whether this pull request can be merged…"
      } else {
        "Merge status is unavailable. Refresh to try again."
      },
    )
  }
  if status.merged {
    return @html.p(
      class="pull-merge-action-state success",
      "✓ This pull request is merged.",
    )
  }
  if !status.open {
    return @html.p(
      class="pull-merge-action-state",
      "○ This pull request is closed.",
    )
  }
  if status.draft {
    return @html.p(
      class="pull-merge-action-state",
      "○ Mark this draft ready for review before merging.",
    )
  }
  if status.mergeable is Some(false) || status.rebaseable is Some(false) {
    return @html.p(
      class="pull-merge-action-state failure",
      "× This branch has conflicts that must be resolved before rebasing.",
    )
  }
  if status.mergeable is None || status.rebaseable is None {
    return @html.p(
      class="pull-merge-action-state pending",
      "● GitHub is still calculating whether this branch can be rebased.",
    )
  }
  if status.mergeable_state == "blocked" {
    return @html.div(class="pull-merge-action-state", [
      @html.p("○ Repository rules currently block this merge."),
      @html.button(
        type_="button",
        class="rebase-merge-button",
        disabled=true,
        "Rebase and merge",
      ),
    ])
  }
  @html.button(
    type_="button",
    class="rebase-merge-button",
    disabled=input.state.loading || input.state.submitting,
    on_click=emit(PullMerge(Submit)),
    if input.state.submitting {
      "Rebasing and merging…"
    } else {
      "Rebase and merge"
    },
  )
}

///|
fn pull_merge_status_view(
  input : PullMergeInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let status = input.state.status
  @html.section(class="pull-merge-card", [
    @html.div(class="pull-merge-header", [
      @html.div([
        @html.p(class="section-label", "Pull request checks"),
        @html.h2("Merge status"),
      ]),
      @html.button(
        type_="button",
        class="secondary compact pull-merge-refresh",
        attrs=@html.Attrs::build().aria_label("Reload merge status"),
        disabled=input.state.loading ||
          input.state.submitting ||
          !(input.auth is SignedIn(..)),
        on_click=emit(PullMerge(Refresh)),
        if input.state.loading {
          "Refreshing…"
        } else {
          "Refresh"
        },
      ),
    ]),
    @html.div(
      class="pull-merge-live",
      attrs=@html.Attrs::build().aria_live("polite").aria_atomic("true"),
      [
        match status {
          Some(status) => ci_status_view(status)
          None =>
            @html.div(class="pull-ci-summary ci-pending", [
              if input.state.loading {
                @html.span(class="spinner", "")
              } else {
                @html.span(
                  class="pull-ci-icon",
                  attrs=@html.Attrs::build().aria_hidden("true"),
                  "○",
                )
              },
              @html.strong(
                if input.state.loading {
                  "Loading CI and merge status…"
                } else if !(input.auth is SignedIn(..)) {
                  "Sign in to load CI and merge status"
                } else {
                  "CI and merge status unavailable"
                },
              ),
            ])
        },
        if input.state.error is Some(message) {
          @html.p(
            class="pull-merge-error",
            attrs=@html.Attrs::build().role("alert"),
            message,
          )
        } else {
          @html.nothing
        },
        @html.div(
          class="pull-merge-actions",
          pull_merge_action_view(input, emit),
        ),
      ],
    ),
  ])
}
