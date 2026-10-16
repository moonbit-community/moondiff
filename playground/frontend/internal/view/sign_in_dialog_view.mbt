///|
fn sign_in_dialog_view(
  input : DiscussionInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let close = emit(
    Ui(CloseSignIn(input.generation, input.sign_in_dialog.revision)),
  )
  @html.dialog(
    id="sign-in-dialog",
    class="sign-in-dialog",
    on_cancel=close,
    attrs=@html.Attrs::build()
      .aria_labelledby("sign-in-dialog-title")
      .data_set("generation", input.generation.to_string())
      .data_set("revision", input.sign_in_dialog.revision.to_string())
      .on_keydown(event => {
        @application.trap_sign_in_focus(event)
        @rabbita.none
      })
      .on_click(event => {
        guard @browser.current_element(event.current_target()) is Some(dialog) &&
          event.target().to_element() is Some(target) &&
          @browser.same(dialog, target) else {
          return @rabbita.none
        }
        let rect = dialog.get_bounding_client_rect()
        if event.get_client_x() < rect.get_left() ||
          event.get_client_x() > rect.get_right() ||
          event.get_client_y() < rect.get_top() ||
          event.get_client_y() > rect.get_bottom() {
          close
        } else {
          @rabbita.none
        }
      }),
    [
      @html.div(class="sign-in-dialog-heading", [
        @html.h2(
          id="sign-in-dialog-title",
          match input.sign_in_dialog.entry {
            Some(Viewed(_)) => "Sign in to track viewed files"
            _ => "Sign in to comment"
          },
        ),
        @html.button(
          type_="button",
          class="sign-in-dialog-close",
          attrs=@html.Attrs::build().aria_label("Close sign-in dialog"),
          on_click=close,
          "×",
        ),
      ]),
      @html.div(
        id="sign-in-dialog-status",
        attrs=@html.Attrs::build()
          .tabindex(-1)
          .role("group")
          .aria_label("GitHub sign-in"),
        if input.sign_in_dialog.entry is Some(_) {
          auth_controls(input.auth, emit)
        } else {
          @html.nothing
        },
      ),
    ],
  )
}
