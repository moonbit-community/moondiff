///|
fn comment_menu(
  id : @comments.CommentId,
  html_url : String,
  review : Session,
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
          toggle_comment_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          comment_menu_button_key(event)
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
          dismiss_comment_menu(event)
          @rabbita.none
        })
        .on_keydown(event => {
          comment_menu_key(event)
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
        if @comments.can_delete_comment(review, id) {
          let conflict = @comments.draft_blocks_deletion(review, id)
          @html.button(
            type_="button",
            class="comment-delete",
            title=if conflict {
              "Send or cancel the reply draft before deleting this comment."
            } else {
              "Delete this comment"
            },
            disabled=review.deletion is Some(Deleting(_)) || conflict,
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
  review : Session,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard @comments.can_delete_comment(review, id) else {
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
  let conflict = @comments.draft_blocks_deletion(review, id)
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

///|
// The native popover lives in the top layer, outside diff-scroll clipping.
// Position it without CSS anchor positioning to retain Chrome 116 support.
extern "js" fn toggle_comment_menu(event : @dom.MouseEvent) -> Unit =
  #| event => {
  #|   event.preventDefault();
  #|   const button = event.currentTarget;
  #|   const menu = button.parentElement.querySelector('.comment-menu');
  #|   button.popoverTargetElement = menu;
  #|   if (menu.matches(':popover-open')) { menu.hidePopover(); return; }
  #|   const rect = button.getBoundingClientRect();
  #|   const controller = new AbortController();
  #|   const options = { signal: controller.signal };
  #|   menu.addEventListener('beforetoggle', event => {
  #|     if (event.newState === 'closed') {
  #|       button.setAttribute('aria-expanded', 'false');
  #|       controller.abort();
  #|     }
  #|   }, options);
  #|   const dismiss = event => {
  #|     if (!menu.isConnected) { controller.abort(); return; }
  #|     if (event.type === 'scroll' && menu.contains(event.target)) return;
  #|     const current = button.getBoundingClientRect();
  #|     // A scroll queued by bringing the trigger into view may arrive after opening.
  #|     if (event.type === 'scroll' && current.top === rect.top && current.right === rect.right) return;
  #|     menu.hidePopover();
  #|     controller.abort();
  #|   };
  #|   window.addEventListener('scroll', dismiss, { ...options, capture: true });
  #|   window.addEventListener('resize', dismiss, options);
  #|   menu.showPopover();
  #|   button.setAttribute('aria-expanded', 'true');
  #|   const box = menu.getBoundingClientRect();
  #|   menu.style.left = Math.max(8, Math.min(rect.right - box.width, innerWidth - box.width - 8)) + 'px';
  #|   const top = rect.bottom + 4 + box.height <= innerHeight - 8 ? rect.bottom + 4 : rect.top - box.height - 4;
  #|   menu.style.top = Math.max(8, Math.min(top, innerHeight - box.height - 8)) + 'px';
  #|   menu.querySelector('[role="menuitem"]:not(:disabled)')?.focus({ preventScroll: true });
  #| }

///|
extern "js" fn dismiss_comment_menu(event : @dom.MouseEvent) -> Unit =
  #| event => {
  #|   if (!event.target.closest('[role="menuitem"]:not(:disabled)')) return;
  #|   const menu = event.currentTarget;
  #|   menu.hidePopover();
  #|   menu.parentElement.querySelector('.comment-more').focus({ preventScroll: true });
  #| }

///|
extern "js" fn comment_menu_button_key(event : @dom.KeyboardEvent) -> Unit =
  #| event => {
  #|   if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
  #|   event.preventDefault();
  #|   const button = event.currentTarget;
  #|   const menu = button.parentElement.querySelector('.comment-menu');
  #|   if (!menu.matches(':popover-open')) button.click();
  #|   const items = menu.querySelectorAll('[role="menuitem"]:not(:disabled)');
  #|   items[event.key === 'ArrowUp' ? items.length - 1 : 0]?.focus({ preventScroll: true });
  #| }

///|
extern "js" fn comment_menu_key(event : @dom.KeyboardEvent) -> Unit =
  #| event => {
  #|   const menu = event.currentTarget;
  #|   if (event.key === 'Escape' || event.key === 'Tab') {
  #|     if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); }
  #|     menu.hidePopover();
  #|     menu.parentElement.querySelector('.comment-more').focus({ preventScroll: true });
  #|     return;
  #|   }
  #|   if (event.key === ' ' && event.target.matches('a[role="menuitem"]')) {
  #|     event.preventDefault(); event.target.click(); return;
  #|   }
  #|   const items = Array.from(menu.querySelectorAll('[role="menuitem"]:not(:disabled)'));
  #|   const index = items.indexOf(document.activeElement);
  #|   let next;
  #|   if (event.key === 'ArrowDown') next = (index + 1) % items.length;
  #|   else if (event.key === 'ArrowUp') next = (index + items.length - 1) % items.length;
  #|   else if (event.key === 'Home') next = 0;
  #|   else if (event.key === 'End') next = items.length - 1;
  #|   else return;
  #|   event.preventDefault();
  #|   items[next]?.focus({ preventScroll: true });
  #| }
