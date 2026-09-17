///|
fn[T] home_page_actions(
  page : @application.HomePage[T],
  noun : String,
  retry : @rabbita.Cmd,
) -> @rabbita.Html {
  @html.div(class="home-page-actions", [
    match page.total {
      Some(total) =>
        @html.p(
          class="home-count",
          "Showing \{page.items.length()} of \{total} \{noun}",
        )
      None => @html.nothing
    },
    match page.load {
      Unloaded | Paused | Loading =>
        @html.div(
          class="home-loading",
          attrs=@html.Attrs::build().role("status"),
          [
            @html.span(class="spinner", ""),
            @html.span(
              if page.refresh is Some(_) {
                "Refreshing…"
              } else {
                "Loading…"
              },
            ),
          ],
        )
      Failed(message) =>
        @html.div(class="home-error", [
          @html.p(
            attrs=@html.Attrs::build().role("alert"),
            if page.refresh is Some(_) {
              "Refresh failed. \{message}"
            } else {
              message
            },
          ),
          @html.button(
            type_="button",
            class="secondary",
            on_click=retry,
            "Retry",
          ),
        ])
      Ready =>
        if page.cursor is Some(_) {
          @html.button(
            type_="button",
            class="secondary",
            on_click=retry,
            "Load more",
          )
        } else {
          @html.nothing
        }
    },
  ])
}

///|
fn home_commit_view(
  value : @application.HomeCommits,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let p = value.pull
  let items : Map[String, @rabbita.Html] = Map([])
  for item in value.page.items {
    let sha = item.sha[:Int::min(7, item.sha.length())].to_owned()
    items[item.sha] = @html.li(class="home-commit", [
      home_link(
        "/\{p.owner}/\{p.repo}/pull/\{p.number}/commits/\{item.sha}",
        "\{sha}  \{item.message}",
        "home-commit-link",
      ),
      @html.div(class="home-meta", [
        @html.span(home_author(item.author)),
        home_time(item.committed_at),
      ]),
    ])
  }
  @html.fragment([
    @html.ul(class="home-commits", items),
    if value.page.load is Ready &&
      value.page.items.is_empty() &&
      value.page.cursor is None {
      @html.p("No commits in this pull request.")
    } else {
      @html.nothing
    },
    if value.page.load is Ready && value.page.cursor is None {
      @html.nothing
    } else {
      home_page_actions(
        value.page,
        "commits",
        emit(Home(LoadCommits(@application.home_pull_key(p)))),
      )
    },
  ])
}

///|
fn home_pull_view(
  pull : @protocol.ApiPullSummary,
  group : String,
  home : @application.HomeState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let key = @application.home_pull_key(pull)
  let value = home.commits.get(key)
  let expanded = value.map(v => v.expanded).unwrap_or(false)
  let id = "\{group}-\{pull.owner}-\{pull.repo}-\{pull.number}-commits"
  let count = match value {
    Some({ page: { total: Some(total), .. }, .. }) => " (\{total})"
    _ => ""
  }
  @html.li(class="home-pull", [
    @html.div(class="home-pull-heading", [
      @html.div(class="home-pull-info", [
        home_link(
          "/\{pull.owner}/\{pull.repo}/pull/\{pull.number}",
          pull.title,
          "home-title-link",
        ),
        @html.div(class="home-meta", [
          @html.span(
            class="home-repository",
            "\{pull.owner}/\{pull.repo} #\{pull.number}",
          ),
          @html.span("by \{home_author(pull.author)}"),
          @html.span([@html.span("Updated "), home_time(pull.updated_at)]),
          if pull.draft {
            @html.span(class="home-draft", "Draft")
          } else {
            @html.nothing
          },
        ]),
      ]),
      @html.button(
        type_="button",
        class="secondary home-expand",
        attrs=@html.Attrs::build()
          .aria_expanded(expanded.to_string())
          .aria_controls(id)
          .aria_label(
            "\{if expanded { "Collapse" } else { "Expand" }} commits\{count} for \{pull.owner}/\{pull.repo} #\{pull.number}",
          ),
        on_click=emit(Home(ToggleCommits(pull))),
        [
          @html.span(
            attrs=@html.Attrs::build().aria_hidden("true"),
            if expanded {
              "▾"
            } else {
              "▸"
            },
          ),
          @html.span("Commits\{count}"),
        ],
      ),
    ]),
    @html.div(
      id~,
      class="home-commit-panel",
      hidden=!expanded,
      match value {
        Some(value) if expanded => home_commit_view(value, emit)
        _ => @html.nothing
      },
    ),
  ])
}
