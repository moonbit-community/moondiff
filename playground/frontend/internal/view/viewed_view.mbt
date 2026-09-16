///|
fn viewed_control(
  is_pull : Bool,
  model : Model,
  index : Int,
  path : String,
) -> ViewedControl {
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
  {
    is_pull,
    generation: model.generation,
    index,
    path,
    checked,
    syncing,
    confirming,
    dismissed,
    disabled,
    title,
    error: match file {
      Some({ pending: None, error, .. }) => error
      _ => None
    },
    retry_disabled: !model.viewed.storage_ready ||
    model.viewed.stale ||
    model.review.snapshot_stale,
  }
}

///|
fn viewed_checkbox_input(
  input : ViewedControl,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard input.is_pull else { return @html.nothing }
  @html.div(class="viewed-control", [
    @html.label(
      class=if input.checked {
        "viewed-label is-viewed"
      } else {
        "viewed-label"
      },
      title=input.title,
      [
        @html.input(
          input_type=Checkbox,
          checked=input.checked,
          attrs=@html.Attrs::build()
            .disabled(input.disabled)
            .aria_label("Viewed \{input.path}")
            .on_click(event => {
              event.stop_propagation()
              emit(Viewed(Toggle(input.generation, input.index)))
            }),
        ),
        @html.span("Viewed"),
        if input.confirming {
          @html.span(
            class="viewed-confirming",
            "Waiting for GitHub confirmation",
          )
        } else if input.syncing {
          @html.span(
            class="viewed-spinner spinner",
            attrs=@html.Attrs::build().aria_label("Syncing Viewed"),
            "",
          )
        } else if input.dismissed {
          @html.span(class="viewed-dismissed", "New changes")
        } else {
          @html.nothing
        },
      ],
    ),
  ])
}

///|
fn viewed_summary_input(
  is_pull : Bool,
  total : Int,
  model : Model,
) -> ViewedSummaryInput {
  {
    is_pull,
    total,
    count: model.viewed.files.filter(f => f.state is Some(Viewed)).length(),
    pending: model.viewed.files.any(f => {
      f.pending is Some({ confirming: true, .. })
    }),
    auth: model.auth,
    ready: model.viewed.ready,
    loading: model.viewed.loading,
    error: model.viewed.error,
    stale: model.viewed.stale || model.review.snapshot_stale,
    poll_scheduled: model.viewed.poll_scheduled,
  }
}

///|
fn viewed_progress_input(
  input : ViewedSummaryInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard input.is_pull else { return @html.nothing }
  @html.div(class="viewed-progress", [
    if !(input.auth is SignedIn(..)) {
      @html.div(class="viewed-sign-in", [
        @html.span("Sign in to track Viewed files."),
        if input.auth is (Anonymous(_) | AuthFailed(_)) {
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
          if input.ready {
            "\{input.count} / \{input.total} files viewed"
          } else if input.error is Some(_) {
            "Viewed status unavailable"
          } else {
            "Loading Viewed status…"
          },
        ),
        if input.ready {
          @html.div(
            class="viewed-progress-track",
            attrs=@html.Attrs::build()
              .role("progressbar")
              .aria_label("Files viewed")
              .aria_valuemin("0")
              .aria_valuemax(input.total.to_string())
              .aria_valuenow(input.count.to_string()),
            @html.div(
              class="viewed-progress-fill",
              style=[
                "width: \{if input.total == 0 { 0 } else { input.count * 100 / input.total }}%",
              ],
              "",
            ),
          )
        } else {
          @html.nothing
        },
        if input.loading && input.ready {
          @html.span(class="viewed-refreshing", "Syncing Viewed…")
        } else {
          @html.nothing
        },
        if input.stale {
          @html.span(
            "PR updated. Load the latest PR to continue marking files.",
          )
        } else {
          @html.nothing
        },
        if input.pending && !input.stale {
          @html.div(class="viewed-confirmation", [
            @html.span(
              if input.loading || input.poll_scheduled {
                "Checking pending Viewed changes with GitHub…"
              } else {
                "Confirmation is paused. Pending files stay locked until GitHub reports the requested state."
              },
            ),
            @html.button(
              type_="button",
              class="secondary",
              disabled=input.loading,
              on_click=emit(Viewed(Refresh)),
              "Recheck Viewed",
            ),
          ])
        } else {
          @html.nothing
        },
        if input.error is Some(message) && !input.stale {
          @html.div(
            class="viewed-error",
            attrs=@html.Attrs::build().role("alert"),
            [
              @html.span(message),
              if !input.pending {
                @html.button(
                  type_="button",
                  class="secondary",
                  disabled=input.loading,
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
fn viewed_error_input(
  input : ViewedControl,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard input.error is Some(message) else { return @html.nothing }
  @html.div(
    class="viewed-file-error",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.span(message),
      @html.button(
        type_="button",
        class="viewed-retry",
        disabled=input.retry_disabled,
        on_click=emit(Viewed(Toggle(input.generation, input.index))),
        "Retry Viewed",
      ),
    ],
  )
}
