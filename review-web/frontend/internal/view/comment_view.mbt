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
fn comment_avatar_url(login : String) -> String {
  let encoded = StringBuilder()
  let hex = b"0123456789ABCDEF"
  for byte in @utf8.encode(login) {
    let n = byte.to_int()
    if (n >= 'a' && n <= 'z') ||
      (n >= 'A' && n <= 'Z') ||
      (n >= '0' && n <= '9') ||
      n == '-' ||
      n == '_' ||
      n == '.' ||
      n == '!' ||
      n == '~' ||
      n == '*' ||
      n == '\'' ||
      n == '(' ||
      n == ')' {
      encoded.write_char(n.unsafe_to_char())
    } else {
      encoded.write_char('%')
      encoded.write_char(hex[n >> 4].to_int().unsafe_to_char())
      encoded.write_char(hex[n & 15].to_int().unsafe_to_char())
    }
  }
  "https://github.com/" + encoded.to_string() + ".png?size=64"
}

///|
fn comment_relative_time(created_at : String) -> String {
  let time = @browser.date_parse(created_at)
  if !@browser.finite(time) {
    return "Unknown time"
  }
  relative_time((@browser.date_now() - time) / 1000.0)
}

///|
fn relative_time(elapsed : Double) -> String {
  let absolute = elapsed.abs()
  if absolute < 60.0 {
    return "just now"
  }
  let units = [
    ("year", 31536000.0),
    ("month", 2592000.0),
    ("day", 86400.0),
    ("hour", 3600.0),
    ("minute", 60.0),
  ]
  for (unit, seconds) in units {
    if absolute >= seconds {
      let count = (absolute / seconds).floor().to_int64()
      let label = "\{count} \{unit}" + (if count == 1L { "" } else { "s" })
      return if elapsed < 0.0 { "in " + label } else { label + " ago" }
    }
  }
  "just now"
}

///|
fn comment_full_time(created_at : String) -> String {
  let time = @browser.date_parse(created_at)
  if @browser.finite(time) {
    @browser.date_utc(time)
  } else {
    "Unknown time"
  }
}

///|
fn comment_body_view(
  author : String,
  created_at : String,
  body : String,
  html_url : String,
  id : @comments.CommentId,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
  markdown? : MarkdownContext,
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
    markdown_view(
      body,
      class="github-comment-body",
      markdown?=markdown.map(context => { ..context, page_url: html_url, }),
    ),
    comment_delete_controls(id, review, emit),
  ])
}

///|
fn comment_editor(
  draft : CommentDraft,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
  unavailable~ : Bool = false,
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
      if !review.permissions.can_comment {
        @html.p(
          class="comment-notice",
          "Sign in with GitHub before posting. Your draft stays editable.",
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
          disabled=unavailable || !review.allowed(Submit),
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
