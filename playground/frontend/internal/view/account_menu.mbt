///|
fn account_menu(
  auth : @application.AuthStatus,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard auth is SignedIn(login~, install_url~, ..) else { return @html.nothing }
  let name = login.unwrap_or("GitHub account")
  @html.div(class="account-control", [
    @html.button(
      type_="button",
      class="secondary account-button",
      title=name,
      attrs=@html.Attrs::build()
        .aria_label("Account: \{name}")
        .aria_haspopup("menu")
        .aria_controls("account-menu")
        .aria_expanded("false")
        .on_click(event => {
          toggle_action_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          action_menu_button_key(event)
          @rabbita.none
        }),
      [
        @html.span(class="account-name", name),
        @html.span(attrs=@html.Attrs::build().aria_hidden("true"), "▾"),
      ],
    ),
    @html.div(
      id="account-menu",
      class="comment-menu account-menu",
      attrs=@html.Attrs::build()
        .popover("auto")
        .role("menu")
        .aria_label("Account")
        .on_click(event => {
          dismiss_action_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          action_menu_key(event)
          @rabbita.none
        }),
      [
        @html.p(
          class="account-identity",
          "Signed in\{login.map(name => " as \{name}").unwrap_or("")}",
        ),
        match install_url {
          Some(url) =>
            @html.div([
              @html.a(
                href=url,
                target=Blank,
                rel="noopener noreferrer",
                attrs=@html.Attrs::build()
                  .role("menuitem")
                  .tabindex(-1)
                  .aria_describedby("account-authorization-hint"),
                "Install Moondiff Github App ↗",
              ),
              @html.p(
                id="account-authorization-hint",
                class="account-hint",
                "Choose which repositories this app can access on GitHub.",
              ),
            ])
          None => @html.nothing
        },
        @html.button(
          type_="button",
          attrs=@html.Attrs::build().role("menuitem").tabindex(-1),
          on_click=emit(Auth(Logout)),
          "Sign out",
        ),
      ],
    ),
  ])
}
