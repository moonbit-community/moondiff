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
  let body_id = "comment-body-" + review.comment_key(id)
  let expanded = review.body_expanded(id)
  let collapsible = match id {
    IssueComment(_) => false
    ReviewComment(_) => true
    CommitComment(id) =>
      review.group.commit_comments.any(c => c.id == id && c.path is Some(_))
  }
  let collapsed = review.comment_collapsed(id)
  @html.article(
    class="github-comment",
    attrs=@html.Attrs::build().data_set("collapsed", collapsed.to_string()),
    [
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
        comment_menu(id, html_url, review, emit, hidden=collapsed),
        if collapsible {
          @html.button(
            id="comment-collapse-" + review.comment_key(id),
            type_="button",
            class="comment-collapse-toggle",
            title=if collapsed { "Expand comment" } else { "Collapse comment" },
            attrs=@html.Attrs::build()
              .aria_label(
                if collapsed {
                  "Expand comment by \{author}"
                } else {
                  "Collapse comment by \{author}"
                },
              )
              .aria_expanded((!collapsed).to_string())
              .aria_controls("comment-details-" + review.comment_key(id))
              .on_click(event => {
                if @browser.current_element(event.current_target())
                  is Some(button) &&
                  button.closest(".github-comment") is Some(card) &&
                  card.query_selector(".comment-menu:popover-open")
                  is Some(menu) {
                  hide_menu(menu)
                }
                @application.set_comment_collapsed(
                  event,
                  review.generation,
                  id,
                  !collapsed,
                  emit,
                )
              }),
            if collapsed {
              "▸"
            } else {
              "▾"
            },
          )
        } else {
          @html.nothing
        },
      ]),
      @html.div(
        id="comment-details-" + review.comment_key(id),
        hidden=collapsed,
        [
          @html.div(
            hidden=collapsed,
            class="github-comment-content",
            attrs=@html.Attrs::build().on_click(event => {
              @application.follow_comment_footnote(
                event,
                review.generation,
                id,
                emit,
              )
            }),
            [
              @html.div(
                id=body_id,
                class="comment-body-clip",
                attrs=@html.Attrs::build().data_set(
                  "expanded",
                  expanded.to_string(),
                ),
                markdown_view(
                  body,
                  class="github-comment-body",
                  scope=review.comment_key(id),
                  markdown?=markdown.map(context => {
                    ..context,
                    page_url: html_url,
                  }),
                ),
              ),
              @html.button(
                type_="button",
                class="comment-body-toggle",
                hidden=true,
                attrs=@html.Attrs::build()
                  .aria_expanded(expanded.to_string())
                  .aria_controls(body_id)
                  .on_click(event => {
                    @application.toggle_comment_body(
                      event,
                      review.generation,
                      id,
                      emit,
                    )
                  }),
                if expanded {
                  "Show less"
                } else {
                  "Show more"
                },
              ),
            ],
          ),
          comment_delete_controls(id, review, emit),
        ],
      ),
    ],
  )
}

///|
fn comment_editor(
  draft : CommentDraft,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
  unavailable~ : Bool = false,
) -> @rabbita.Html {
  comment_editor_view(Some(draft), review, emit, unavailable~)
}

///|
// The overall composer uses the same tree before and after its first input.
// Draft identity is an attribute, never a key that could replace the textarea.
fn comment_editor_view(
  draft : CommentDraft?,
  review : @comments.ReadView,
  emit : @rabbita.Emit[Msg],
  overall~ : Bool = false,
  unavailable~ : Bool = false,
) -> @rabbita.Html {
  let blocked = overall &&
    review.permissions.target is Some(kind) &&
    !(kind is OverallDraft)
  let submitting = draft.map(draft => draft.submitting).unwrap_or(false)
  let attrs = @html.Attrs::build()
  let textarea_attrs = @html.Attrs::build().aria_label(
    if overall {
      "Add a comment"
    } else if draft is Some({ kind: ReplyDraft(_), .. }) {
      "Write a reply"
    } else {
      "Leave a comment"
    },
  )
  if draft is Some(draft) {
    attrs.data_set("draft-id", draft.id.key()) |> ignore
    textarea_attrs.data_set("draft-id", draft.id.key()) |> ignore
  }
  if blocked {
    textarea_attrs.aria_describedby("overall-comment-notice") |> ignore
  }
  @html.div(
    class=if overall {
      "comment-editor overall-comment-editor"
    } else {
      "comment-editor"
    },
    attrs~,
    [
      comment_avatar(review.login),
      @html.div(class="comment-editor-content", [
        if overall {
          @html.h3(class="comment-editor-title", "Add a comment")
        } else {
          @html.nothing
        },
        @html.textarea(
          class="comment-textarea",
          value=draft.map(draft => draft.body).unwrap_or(""),
          rows=4,
          maxlength=65_536,
          placeholder="Leave a comment",
          attrs=textarea_attrs,
          disabled=submitting ||
            blocked ||
            (draft is None && !review.allowed(OpenDraft(OverallDraft))),
          on_input=value => {
            emit(
              Review(
                if overall {
                  OverallDraftBodyChanged(value)
                } else {
                  DraftBodyChanged(value)
                },
              ),
            )
          },
          "",
        ),
        if draft is Some({ error: Some(message), .. }) {
          @html.p(
            class="comment-error",
            attrs=@html.Attrs::build().role("alert"),
            message,
          )
        } else {
          @html.nothing
        },
        if blocked {
          @html.p(
            id="overall-comment-notice",
            class="comment-notice",
            "Post or cancel your current draft before adding an overall comment.",
          )
        } else if !review.permissions.can_comment {
          @html.p(
            class="comment-notice",
            if review.permissions.identity_checking {
              "Checking your GitHub account. You can keep writing."
            } else {
              "Sign in with GitHub before posting. Your draft stays editable."
            },
          )
        } else {
          @html.nothing
        },
        @html.div(class="comment-editor-actions", [
          if draft is Some(_) {
            @html.button(
              type_="button",
              class="comment-cancel",
              disabled=submitting,
              on_click=emit(Review(CancelDraft)),
              "Cancel",
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            class="comment-submit",
            disabled=draft is None || unavailable || !review.allowed(Submit),
            on_click=emit(Review(SubmitDraft)),
            if submitting {
              "Posting…"
            } else {
              "Post comment"
            },
          ),
        ]),
      ]),
    ],
  )
}
