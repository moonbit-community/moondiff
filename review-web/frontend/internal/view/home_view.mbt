///|
fn home_date(value : String) -> String {
  let time = @browser.date_parse(value)
  if @browser.finite(time) {
    @browser.date_local(time)
  } else {
    value
  }
}

///|
fn home_time(value : String) -> @rabbita.Html {
  @html.time(datetime=value, title=value, home_date(value))
}

///|
fn home_author(value : String) -> String {
  if value.is_empty() {
    "Unknown author"
  } else {
    value
  }
}

///|
fn home_tab_id(kind : @protocol.ViewerPullKind) -> String {
  match kind {
    ReviewRequested => "review"
    Authored => "authored"
  }
}

///|
fn home_tab_title(kind : @protocol.ViewerPullKind) -> String {
  match kind {
    ReviewRequested => "Review requests"
    Authored => "Pull requests authored by me"
  }
}

///|
fn home_tab(
  kind : @protocol.ViewerPullKind,
  page : @application.HomePage[@protocol.ApiPullSummary],
  home : @application.HomeState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let id = home_tab_id(kind)
  let selected = home.tab == kind
  @html.button(
    id="home-tab-\{id}",
    type_="button",
    class="secondary home-tab",
    attrs=@html.Attrs::build()
      .role("tab")
      .aria_controls("home-panel-\{id}")
      .aria_selected(selected.to_string())
      .tabindex(if selected { 0 } else { -1 }),
    on_click=emit(Home(SelectTab(kind))),
    [
      @html.span(home_tab_title(kind)),
      @html.span(
        class="home-tab-count",
        attrs=if page.total is Some(_) {
          @html.Attrs::build()
        } else {
          @html.Attrs::build().aria_label(
            if page.load is Failed(_) {
              "Count unavailable"
            } else {
              "Loading count"
            },
          )
        },
        page.total
        .map(total => total.to_string())
        .unwrap_or(if page.load is Failed(_) { "—" } else { "…" }),
      ),
    ],
  )
}

///|
fn home_tab_key(event : @dom.KeyboardEvent) -> Unit {
  guard @browser.current_element(event.current_target()) is Some(parent) else {
    return
  }
  let tabs = parent.query_selector_all("[role=\"tab\"]").iter().collect()
  guard event.target().to_element() is Some(target) else { return }
  guard tabs.search_by(tab => @browser.same(tab, target)) is Some(index) else {
    return
  }
  let next = match event.key() {
    "ArrowRight" => (index + 1) % tabs.length()
    "ArrowLeft" => (index + tabs.length() - 1) % tabs.length()
    "Home" => 0
    "End" => tabs.length() - 1
    _ => return
  }
  event.prevent_default()
  @browser.focus(tabs[next])
  @browser.click(tabs[next])
}

///|
fn home_group(
  kind : @protocol.ViewerPullKind,
  home : @application.HomeState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let (page, empty, scope) = match kind {
    ReviewRequested =>
      (
        home.reviews,
        "No pull requests awaiting your review.",
        "Open pull requests that request your review appear here.",
      )
    Authored =>
      (
        home.authored,
        "You have no open pull requests.",
        "Pull requests you created appear here. Closed and merged pull requests are not included.",
      )
  }
  let group = home_tab_id(kind)
  let items : Map[String, @rabbita.Html] = Map([])
  for pull in page.items {
    items[@application.home_pull_key(pull)] = home_pull_view(
      pull, group, home, emit,
    )
  }
  @html.section(
    id="home-panel-\{group}",
    class="home-group",
    hidden=home.tab != kind,
    attrs=@html.Attrs::build()
      .role("tabpanel")
      .aria_labelledby("home-tab-\{group}")
      .tabindex(0),
    [
      @html.ul(class="home-pulls", items),
      home_page_actions(page, "pull requests", emit(Home(LoadPulls(kind)))),
      if page.load is Ready && page.items.is_empty() && page.cursor is None {
        @html.div(class="home-empty", [
          @html.p(class="home-empty-title", empty),
          @html.p(scope),
        ])
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn home_view(
  auth : @application.AuthStatus,
  home : @application.HomeState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if auth is AuthChecking {
    return @html.div(
      class="home-session-loading",
      attrs=@html.Attrs::build().role("status"),
      [
        @html.span(class="spinner", ""),
        @html.span("Checking GitHub session…"),
      ],
    )
  }
  let page = match home.tab {
    ReviewRequested => home.reviews
    Authored => home.authored
  }
  let busy = home.busy()
  let refreshing = home.reviews.refresh is Some(_) ||
    home.authored.refresh is Some(_) ||
    home.commits
    .values()
    .any(value => value.expanded && value.page.refresh is Some(_))
  @html.div(class="pr-dashboard", [
    @html.header(class="home-header", [
      @html.h1(class="home-identity", "Moondiff Review"),
      account_menu(auth, emit),
    ]),
    @html.div(
      class="home-tabs",
      attrs=@html.Attrs::build()
        .role("tablist")
        .aria_label("Pull requests")
        .on_keydown(event => {
          home_tab_key(event)
          @rabbita.none
        }),
      [
        home_tab(Authored, home.authored, home, emit),
        home_tab(ReviewRequested, home.reviews, home, emit),
      ],
    ),
    @html.div(class="home-toolbar", [
      @html.span(
        class="home-updated",
        if page.updated_at is Some(value) {
          @html.fragment([@html.span("Last updated "), home_time(value)])
        } else {
          @html.nothing
        },
      ),
      @html.button(
        type_="button",
        class="secondary",
        disabled=busy,
        on_click=emit(Home(Refresh)),
        if busy {
          if refreshing {
            "Refreshing…"
          } else {
            "Loading…"
          }
        } else {
          "Refresh lists"
        },
      ),
    ]),
    home_group(Authored, home, emit),
    home_group(ReviewRequested, home, emit),
  ])
}
