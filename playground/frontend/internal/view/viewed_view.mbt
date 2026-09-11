///|
fn viewed_checkbox(
  commit : ChangeView,
  model : Model,
  index : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard commit.reference.target is PullRequest(_) else { return @html.nothing }
  let file = model.viewed.files.get(index)
  let checked = file is Some({ state: Some(Viewed), .. })
  let syncing = file is Some({ pending: Some(_), .. })
  let confirming = file is Some({ pending: Some({ confirming: true, .. }), .. })
  let dismissed = file is Some({ state: Some(Dismissed), .. })
  let disabled = !(model.auth is SignedIn(..)) ||
    !model.viewed.ready ||
    !model.viewed.storage_ready ||
    syncing ||
    model.viewed.stale ||
    model.review.snapshot_stale
  let title = if !(model.auth is SignedIn(..)) {
    "Sign in to sync Viewed files with GitHub"
  } else if model.viewed.stale || model.review.snapshot_stale {
    "PR updated. Load the latest PR before marking files."
  } else if confirming {
    "Waiting for GitHub confirmation"
  } else if syncing {
    "Syncing Viewed with GitHub…"
  } else if !model.viewed.ready {
    "Waiting for Viewed state from GitHub"
  } else if dismissed {
    "New changes since last viewed"
  } else {
    "Mark file as viewed"
  }
  @html.div(class="viewed-control", [
    @html.label(
      class=if checked { "viewed-label is-viewed" } else { "viewed-label" },
      title~,
      [
        @html.input(
          input_type=Checkbox,
          checked~,
          attrs=@html.Attrs::build()
            .disabled(disabled)
            .aria_label("Viewed \{commit.files[index].file.filename}")
            .on_click(event => {
              event.stop_propagation()
              emit(Viewed(Toggle(model.generation, index)))
            }),
        ),
        @html.span("Viewed"),
        if confirming {
          @html.span(
            class="viewed-confirming",
            "Waiting for GitHub confirmation",
          )
        } else if syncing {
          @html.span(
            class="viewed-spinner spinner",
            attrs=@html.Attrs::build().aria_label("Syncing Viewed"),
            "",
          )
        } else if dismissed {
          @html.span(class="viewed-dismissed", "New changes")
        } else {
          @html.nothing
        },
      ],
    ),
  ])
}

///|
fn viewed_progress(
  commit : ChangeView,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard commit.reference.target is PullRequest(_) else { return @html.nothing }
  let count = model.viewed.files
    .filter(file => file.state is Some(Viewed))
    .length()
  let total = commit.files.length()
  let pending = model.viewed.files.any(file => {
    file.pending is Some({ confirming: true, .. })
  })
  @html.div(class="viewed-progress", [
    if !(model.auth is SignedIn(..)) {
      @html.div(class="viewed-sign-in", [
        @html.span("Sign in to track Viewed files."),
        if model.auth is (Anonymous(_) | AuthFailed(_)) {
          @html.button(
            type_="button",
            class="secondary",
            on_click=emit(Auth(StartSignIn)),
            "Sign in to sync Viewed",
          )
        } else {
          @html.nothing
        },
      ])
    } else {
      @html.div(class="viewed-progress-content", [
        @html.span(
          attrs=@html.Attrs::build().role("status"),
          if model.viewed.ready {
            "\{count} / \{total} files viewed"
          } else if model.viewed.error is Some(_) {
            "Viewed status unavailable"
          } else {
            "Loading Viewed status…"
          },
        ),
        if model.viewed.ready {
          @html.div(
            class="viewed-progress-track",
            attrs=@html.Attrs::build()
              .role("progressbar")
              .aria_label("Files viewed")
              .aria_valuemin("0")
              .aria_valuemax(total.to_string())
              .aria_valuenow(count.to_string()),
            @html.div(
              class="viewed-progress-fill",
              style=[
                "width: \{if total == 0 { 0 } else { count * 100 / total }}%",
              ],
              "",
            ),
          )
        } else {
          @html.nothing
        },
        if model.viewed.loading && model.viewed.ready {
          @html.span(class="viewed-refreshing", "Syncing Viewed…")
        } else {
          @html.nothing
        },
        if model.viewed.stale || model.review.snapshot_stale {
          @html.span(
            "PR updated. Load the latest PR to continue marking files.",
          )
        } else {
          @html.nothing
        },
        if pending && !model.viewed.stale && !model.review.snapshot_stale {
          @html.div(class="viewed-confirmation", [
            @html.span(
              if model.viewed.loading || model.viewed.poll_scheduled {
                "Checking pending Viewed changes with GitHub…"
              } else {
                "Confirmation is paused. Pending files stay locked until GitHub reports the requested state."
              },
            ),
            @html.button(
              type_="button",
              class="secondary",
              disabled=model.viewed.loading,
              on_click=emit(Viewed(Refresh)),
              "Recheck Viewed",
            ),
          ])
        } else {
          @html.nothing
        },
        if model.viewed.error is Some(message) &&
          !model.viewed.stale &&
          !model.review.snapshot_stale {
          @html.div(
            class="viewed-error",
            attrs=@html.Attrs::build().role("alert"),
            [
              @html.span(message),
              if !pending {
                @html.button(
                  type_="button",
                  class="secondary",
                  disabled=model.viewed.loading,
                  on_click=emit(Viewed(Refresh)),
                  "Retry Viewed sync",
                )
              } else {
                @html.nothing
              },
            ],
          )
        } else {
          @html.nothing
        },
      ])
    },
  ])
}

///|
fn viewed_file_error(
  model : Model,
  index : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard model.viewed.files.get(index)
    is Some({ error: Some(message), pending: None, .. }) else {
    return @html.nothing
  }
  @html.div(
    class="viewed-file-error",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.span(message),
      @html.button(
        type_="button",
        class="viewed-retry",
        disabled=!model.viewed.storage_ready ||
          model.viewed.stale ||
          model.review.snapshot_stale,
        on_click=emit(Viewed(Toggle(model.generation, index))),
        "Retry Viewed",
      ),
    ],
  )
}
