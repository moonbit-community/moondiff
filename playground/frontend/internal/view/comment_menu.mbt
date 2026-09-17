///|
fn comment_menu(
  id : @comments.CommentId,
  html_url : String,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let menu_id = "comment-menu:\{review.comment_key(id)}"
  @html.div(class="comment-actions", [
    @html.button(
      type_="button",
      class="comment-more",
      title="More options",
      attrs=@html.Attrs::build()
        .aria_label("More options")
        .aria_haspopup("menu")
        .aria_controls(menu_id)
        .aria_expanded("false")
        .on_click(event => {
          toggle_action_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          action_menu_button_key(event)
          @rabbita.none
        }),
      "⋯",
    ),
    @html.div(
      id=menu_id,
      class="comment-menu",
      attrs=@html.Attrs::build()
        .popover("auto")
        .role("menu")
        .aria_label("Comment options")
        .on_click(event => {
          dismiss_action_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          action_menu_key(event)
          @rabbita.none
        }),
      [
        @html.a(
          href=html_url,
          target=Blank,
          rel="noopener noreferrer",
          attrs=@html.Attrs::build().role("menuitem").tabindex(-1),
          "Open on GitHub ↗",
        ),
        if review.can_delete(id) {
          let conflict = review.draft_blocks_deletion(id)
          @html.button(
            type_="button",
            class="comment-delete",
            title=if conflict {
              "Send or cancel the reply draft before deleting this comment."
            } else {
              "Delete this comment"
            },
            disabled=review.permissions.deleting || conflict,
            attrs=@html.Attrs::build().role("menuitem").tabindex(-1),
            on_click=emit(Review(AskDelete(id))),
            "Delete",
          )
        } else {
          @html.nothing
        },
      ],
    ),
  ])
}

///|
fn comment_delete_controls(
  id : @comments.CommentId,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard review.can_delete(id) else {
    if review.deletion is Some(DeleteFailed(selected, message)) &&
      selected == id {
      return @html.p(class="comment-error", message)
    }
    return @html.nothing
  }
  let selected = match review.deletion {
    Some(ConfirmDelete(current))
    | Some(Deleting(current))
    | Some(DeleteFailed(current, _)) => current == id
    _ => false
  }
  let conflict = review.draft_blocks_deletion(id)
  let hint = if conflict {
    "Send or cancel the reply draft before deleting this comment."
  } else {
    "Delete this comment"
  }
  let busy = review.deletion is Some(Deleting(_))
  if !selected {
    return @html.nothing
  }
  @html.div(class="comment-delete-actions", [
    @html.span("Delete this comment?"),
    @html.button(
      type_="button",
      class="comment-cancel",
      disabled=busy,
      on_click=emit(Review(CancelDelete)),
      "Cancel deletion",
    ),
    @html.button(
      type_="button",
      class="comment-delete-confirm",
      disabled=busy || conflict,
      title=hint,
      on_click=emit(Review(ConfirmCommentDelete(id))),
      if busy {
        "Deleting…"
      } else {
        "Confirm delete"
      },
    ),
    match review.deletion {
      Some(DeleteFailed(_, error)) => @html.p(class="comment-error", error)
      _ => @html.nothing
    },
  ])
}
