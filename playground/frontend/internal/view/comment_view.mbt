///|
// A background image leaves the silhouette visible if GitHub cannot load it.
fn comment_avatar(login : String?) -> @rabbita.Html {
  @html.span(
    class="comment-avatar",
    attrs=@html.Attrs::build().aria_hidden("true"),
    [
      @html.span(class="comment-avatar-placeholder", ""),
      if login is Some(login) {
        @html.span(
          class="comment-avatar-image",
          style=["background-image: url(\{comment_avatar_url(login)})"],
          "",
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
extern "js" fn comment_avatar_url(login : String) -> String =
  #| login => 'https://github.com/' + encodeURIComponent(login) + '.png?size=64'

///|
extern "js" fn comment_relative_time(created_at : String) -> String =
  #| value => {
  #|   const time = Date.parse(value);
  #|   if (!Number.isFinite(time)) return 'Unknown time';
  #|   const elapsed = (Date.now() - time) / 1000;
  #|   if (Math.abs(elapsed) < 60) return 'just now';
  #|   const units = [['year', 31536000], ['month', 2592000], ['day', 86400], ['hour', 3600], ['minute', 60]];
  #|   const [unit, seconds] = units.find(([, seconds]) => Math.abs(elapsed) >= seconds);
  #|   const count = Math.floor(Math.abs(elapsed) / seconds);
  #|   const label = count + ' ' + unit + (count === 1 ? '' : 's');
  #|   return elapsed < 0 ? 'in ' + label : label + ' ago';
  #| }

///|
extern "js" fn comment_full_time(created_at : String) -> String =
  #| value => {
  #|   const time = Date.parse(value);
  #|   return Number.isFinite(time) ? new Date(time).toUTCString() : 'Unknown time';
  #| }

///|
fn comment_body_view(
  author : String,
  created_at : String,
  body : String,
  html_url : String,
  id : @comments.CommentId,
  review : Session,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.article(class="github-comment", [
    @html.div(class="github-comment-meta", [
      comment_avatar(if author == "ghost" { None } else { Some(author) }),
      @html.div(class="comment-byline", [
        @html.strong(author),
        @html.time(
          datetime=created_at,
          title=comment_full_time(created_at),
          comment_relative_time(created_at),
        ),
      ]),
      comment_menu(id, html_url, review, emit),
    ]),
    @html.p(class="github-comment-body", body),
    comment_delete_controls(id, review, emit),
  ])
}

///|
fn comment_editor(
  draft : CommentDraft,
  review : Session,
  emit : @rabbita.Emit[Msg],
  unavailable? : Bool = false,
) -> @rabbita.Html {
  @html.div(class="comment-editor", [
    comment_avatar(review.login),
    @html.div(class="comment-editor-content", [
      @html.textarea(
        class="comment-textarea",
        value=draft.body,
        rows=4,
        maxlength=65_536,
        placeholder="Leave a comment",
        attrs=@html.Attrs::build()
          .data_set("draft-id", draft.id.key())
          .aria_label(
            if draft.kind is ReplyDraft(_) {
              "Write a reply"
            } else {
              "Leave a comment"
            },
          ),
        disabled=draft.submitting,
        on_input=value => emit(Review(DraftBodyChanged(value))),
        "",
      ),
      if draft.error is Some(message) {
        @html.p(
          class="comment-error",
          attrs=@html.Attrs::build().role("alert"),
          message,
        )
      } else {
        @html.nothing
      },
      @html.div(class="comment-editor-actions", [
        @html.button(
          type_="button",
          class="comment-cancel",
          disabled=draft.submitting,
          on_click=emit(Review(CancelDraft)),
          "Cancel",
        ),
        @html.button(
          type_="button",
          class="comment-submit",
          disabled=unavailable ||
            !@comments.permission(review, Submit).allowed(),
          on_click=emit(Review(SubmitDraft)),
          if draft.submitting {
            "Posting…"
          } else {
            "Post comment"
          },
        ),
      ]),
    ]),
  ])
}
