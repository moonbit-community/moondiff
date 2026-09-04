///|
fn review_segment_nodes(
  text : String?,
  segments : ArrayView[@model.DiffSegment]?,
  changed_class : String,
  prefix : String,
) -> Array[@rabbita.Html] {
  let nodes : Array[@rabbita.Html] = []
  if !prefix.is_empty() {
    nodes.push(@html.span(class="diff-prefix", prefix))
  }
  if segments is Some(segments) {
    for segment in segments {
      nodes.push(
        match segment.kind {
          Unchanged => @html.span(segment.text)
          Changed => @html.b(class=changed_class, segment.text)
          Ignored => @html.span(class="ignored-context", segment.text)
        },
      )
    }
  } else {
    nodes.push(@html.span(text.unwrap_or("")))
  }
  nodes
}

///|
fn inline_draft_for_anchor(
  review : ReviewState,
  anchor : ReviewAnchor?,
) -> CommentDraft? {
  guard review_can_comment(review) &&
    anchor is Some(anchor) &&
    review.draft is Some(draft) else {
    return None
  }
  match draft.kind {
    InlineDraft(_, selected) if selected == anchor => Some(draft)
    _ => None
  }
}

///|
fn review_gutter(
  file_index : Int,
  number : Int?,
  anchor : ReviewAnchor?,
  class_name : String,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.td(class="line-number review-gutter \{class_name}", [
    @html.span(
      class="line-number-value",
      number.map(value => value.to_string()).unwrap_or(""),
    ),
    if review_can_comment(review) && anchor is Some(anchor) {
      @html.button(
        type_="button",
        class="line-comment-button",
        title="Comment on line \{anchor.line}",
        attrs=@html.Attrs::build().aria_label("Comment on line \{anchor.line}"),
        on_click=emit(Review(OpenInlineDraft(file_index, anchor))),
        "+",
      )
    } else {
      @html.nothing
    },
  ])
}

///|
fn comment_editor(
  draft : CommentDraft,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.div(class="comment-editor", [
    @html.textarea(
      class="comment-textarea",
      value=draft.body,
      rows=4,
      maxlength=65_536,
      placeholder="Leave a comment",
      autofocus=true,
      disabled=draft.submitting,
      on_input=value => emit(Review(DraftBodyChanged(value))),
      "",
    ),
    if draft.error is Some(message) {
      @html.p(class="comment-error", message)
    } else {
      @html.nothing
    },
    @html.div(class="comment-editor-actions", [
      @html.button(
        type_="button",
        class="secondary",
        disabled=draft.submitting,
        on_click=emit(Review(CancelDraft)),
        "Cancel",
      ),
      @html.button(
        type_="button",
        class="comment-submit",
        disabled=draft.submitting || draft.body.trim().is_empty(),
        on_click=emit(Review(SubmitDraft)),
        if draft.submitting {
          "Posting…"
        } else {
          "Post comment"
        },
      ),
    ]),
  ])
}

///|
fn inline_editor_row(
  review : ReviewState,
  anchor : ReviewAnchor?,
  columns : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if inline_draft_for_anchor(review, anchor) is Some(draft) {
    @html.tr(class="inline-comment-editor-row", [
      @html.td(colspan=columns, comment_editor(draft, emit)),
    ])
  } else {
    @html.nothing
  }
}

///|
fn review_row_classes(row : ReviewRow) -> (String, String) {
  match row.kind {
    ContextRow => ("ctx", "ctx")
    IgnoredRow => ("ctx ignored", "ctx ignored")
    ChangeRow =>
      (
        if row.old_line is Some(_) {
          "del"
        } else {
          "empty"
        },
        if row.new_line is Some(_) {
          "add"
        } else {
          "empty"
        },
      )
  }
}

///|
fn split_review_line(
  row : ReviewRow,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Html] {
  let (old_class, new_class) = review_row_classes(row)
  let items : Array[@rabbita.Html] = [
    @html.tr([
      review_gutter(
        row.file_index,
        row.old_line,
        row.old_anchor,
        "old-line-number",
        review,
        emit,
      ),
      @html.td(
        class=old_class,
        review_segment_nodes(row.old_text, row.old_segments, "wd", ""),
      ),
      review_gutter(
        row.file_index,
        row.new_line,
        row.new_anchor,
        "new-line-number",
        review,
        emit,
      ),
      @html.td(
        class=new_class,
        review_segment_nodes(row.new_text, row.new_segments, "wa", ""),
      ),
    ]),
  ]
  if inline_draft_for_anchor(review, row.old_anchor) is Some(_) {
    items.push(inline_editor_row(review, row.old_anchor, 4, emit))
  } else if inline_draft_for_anchor(review, row.new_anchor) is Some(_) {
    items.push(inline_editor_row(review, row.new_anchor, 4, emit))
  }
  items
}

///|
fn unified_source_line(
  file_index : Int,
  old_line : Int?,
  new_line : Int?,
  anchor : ReviewAnchor?,
  class_name : String,
  text : String?,
  segments : ArrayView[@model.DiffSegment]?,
  changed_class : String,
  prefix : String,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Html] {
  let items : Array[@rabbita.Html] = [
    @html.tr([
      review_gutter(
        file_index,
        old_line,
        if anchor.map(a => a.side is Left).unwrap_or(false) {
          anchor
        } else {
          None
        },
        "old-line-number",
        review,
        emit,
      ),
      review_gutter(
        file_index,
        new_line,
        if anchor.map(a => a.side is Right).unwrap_or(false) {
          anchor
        } else {
          None
        },
        "new-line-number",
        review,
        emit,
      ),
      @html.td(
        class=class_name,
        review_segment_nodes(text, segments, changed_class, prefix),
      ),
    ]),
  ]
  if inline_draft_for_anchor(review, anchor) is Some(_) {
    items.push(inline_editor_row(review, anchor, 3, emit))
  }
  items
}

///|
fn unified_review_line(
  row : ReviewRow,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Html] {
  match row.kind {
    ContextRow =>
      unified_source_line(
        row.file_index,
        row.old_line,
        row.new_line,
        row.new_anchor,
        "ctx",
        row.new_text,
        row.new_segments,
        "wa",
        " ",
        review,
        emit,
      )
    IgnoredRow =>
      if row.old_text == row.new_text {
        unified_source_line(
          row.file_index,
          row.old_line,
          row.new_line,
          row.new_anchor,
          "ctx ignored",
          row.new_text,
          row.new_segments,
          "wa",
          " ",
          review,
          emit,
        )
      } else {
        let items = unified_source_line(
          row.file_index,
          row.old_line,
          None,
          row.old_anchor,
          "ctx ignored",
          row.old_text,
          row.old_segments,
          "wd",
          " ",
          review,
          emit,
        )
        items.push_iter(
          unified_source_line(
            row.file_index,
            None,
            row.new_line,
            row.new_anchor,
            "ctx ignored",
            row.new_text,
            row.new_segments,
            "wa",
            " ",
            review,
            emit,
          ).iter(),
        )
        items
      }
    ChangeRow => {
      let items : Array[@rabbita.Html] = []
      if row.old_line is Some(_) {
        items.push_iter(
          unified_source_line(
            row.file_index,
            row.old_line,
            None,
            row.old_anchor,
            "del",
            row.old_text,
            row.old_segments,
            "wd",
            "-",
            review,
            emit,
          ).iter(),
        )
      }
      if row.new_line is Some(_) {
        items.push_iter(
          unified_source_line(
            row.file_index,
            None,
            row.new_line,
            row.new_anchor,
            "add",
            row.new_text,
            row.new_segments,
            "wa",
            "+",
            review,
            emit,
          ).iter(),
        )
      }
      items
    }
  }
}

///|
fn safe_review_diff(
  file : ApiFile,
  file_index : Int,
  document : @model.HunkDocument,
  mode : ViewMode,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
  old_base? : Int = 0,
  new_base? : Int = 0,
  show_hunk_headers? : Bool = true,
  hunk_context? : String = "",
) -> @rabbita.Html {
  let patch = parse_canonical_patch(file.filename, file.patch)
  let rows : Array[@rabbita.Html] = []
  for
    item in project_review_items(
      file_index,
      file.filename,
      document,
      patch,
      old_base~,
      new_base~,
      show_hunk_headers~,
      hunk_context~,
    ) {
    match item {
      ReviewHunk(header) =>
        rows.push(
          @html.tr([
            @html.td(
              class="hunk-header",
              colspan=if mode is Split { 4 } else { 3 },
              header,
            ),
          ]),
        )
      ReviewLine(row) => {
        // Keep the actual file index even though the gutter only needs the
        // canonical anchor. This makes the selected draft stable across views.
        let row = { ..row, file_index, }
        let rendered = match mode {
          Split => split_review_line(row, review, emit)
          Unified => unified_review_line(row, review, emit)
        }
        rows.push_iter(rendered.iter())
      }
    }
  }
  @html.div(class="diff-scroll", [
    @html.table(
      class=if mode is Split {
        "split review-diff"
      } else {
        "unified numbered review-diff"
      },
      @html.tbody(rows),
    ),
  ])
}

///|
fn comment_body_view(
  author : String,
  created_at : String,
  body : String,
  html_url : String,
) -> @rabbita.Html {
  @html.article(class="github-comment", [
    @html.div(class="github-comment-meta", [
      @html.strong(author),
      @html.span(created_at),
      @html.a(
        href=html_url,
        target=Blank,
        rel="noopener noreferrer",
        "Open on GitHub ↗",
      ),
    ]),
    @html.p(class="github-comment-body", body),
  ])
}

///|
fn review_thread_view(
  thread : ReviewThread,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let can_comment = review_can_comment(review)
  let comments : Array[@rabbita.Html] = [
    comment_body_view(
      author_label(thread.root.user),
      thread.root.created_at,
      thread.root.body,
      thread.root.html_url,
    ),
  ]
  for reply in thread.replies {
    comments.push(
      comment_body_view(
        author_label(reply.user),
        reply.created_at,
        reply.body,
        reply.html_url,
      ),
    )
  }
  if can_comment {
    comments.push(
      @html.button(
        type_="button",
        class="comment-reply-button",
        on_click=emit(Review(OpenReplyDraft(thread.root.id))),
        "Reply",
      ),
    )
  }
  if can_comment &&
    review.draft is Some(draft) &&
    draft.kind is ReplyDraft(id) &&
    id == thread.root.id {
    comments.push(comment_editor(draft, emit))
  }
  @html.div(class="review-thread", comments)
}

///|
fn file_discussions_view(
  view : ChangeView,
  file_index : Int,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  guard review.comments is CommentsReady(bundle) else { return @html.nothing }
  match view.reference.target {
    PullRequest(_) => {
      let active : Array[@rabbita.Html] = []
      let outdated : Array[@rabbita.Html] = []
      for thread in review_threads(view, bundle.review_comments) {
        if thread.file_index == Some(file_index) {
          if thread.outdated {
            outdated.push(review_thread_view(thread, review, emit))
          } else {
            active.push(review_thread_view(thread, review, emit))
          }
        }
      }
      if active.is_empty() && outdated.is_empty() {
        return @html.nothing
      }
      @html.section(class="file-discussions", [
        if !active.is_empty() {
          @html.div(class="active-discussions", [
            @html.h3("Discussion"),
            @html.div(active),
          ])
        } else {
          @html.nothing
        },
        if !outdated.is_empty() {
          @html.div(class="outdated-discussions", [
            @html.h3("Outdated discussion"),
            @html.p(
              "These comments no longer map to the current canonical patch.",
            ),
            @html.div(outdated),
          ])
        } else {
          @html.nothing
        },
      ])
    }
    Commit(_) | PullCommit(_, _) => {
      let active : Array[@rabbita.Html] = []
      let outdated : Array[@rabbita.Html] = []
      for discussion in commit_discussions(view, bundle.commit_comments) {
        if discussion.file_index == Some(file_index) {
          let rendered = comment_body_view(
            author_label(discussion.comment.user),
            discussion.comment.created_at,
            discussion.comment.body,
            discussion.comment.html_url,
          )
          if discussion.outdated {
            outdated.push(rendered)
          } else {
            active.push(rendered)
          }
        }
      }
      if active.is_empty() && outdated.is_empty() {
        return @html.nothing
      }
      @html.section(class="file-discussions", [
        if !active.is_empty() {
          @html.div(class="active-discussions", [
            @html.h3("Commit comments"),
            @html.div(active),
          ])
        } else {
          @html.nothing
        },
        if !outdated.is_empty() {
          @html.div(class="outdated-discussions", [
            @html.h3("Outdated comments"),
            @html.p("These comments no longer map to the canonical patch."),
            @html.div(outdated),
          ])
        } else {
          @html.nothing
        },
      ])
    }
  }
}

///|
fn auth_controls(
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match review.auth {
    WebReadOnly => @html.nothing
    AuthChecking =>
      @html.span(class="auth-status", "Checking GitHub session…")
    SignedIn(login~, install_url~) =>
      @html.div(class="auth-controls", [
        @html.span("Signed in\{login.map(name => " as \{name}").unwrap_or("")}"),
        if install_url is Some(url) {
          @html.a(
            href=url,
            target=Blank,
            rel="noopener noreferrer",
            "Install GitHub App ↗",
          )
        } else {
          @html.nothing
        },
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Auth(Logout)),
          "Sign out",
        ),
      ])
    Anonymous(install_url) =>
      @html.div(class="auth-controls", [
        @html.button(
          type_="button",
          class="comment-submit",
          on_click=emit(Auth(StartDeviceAuthorization)),
          "Sign in with GitHub",
        ),
        if install_url is Some(url) {
          @html.a(
            href=url,
            target=Blank,
            rel="noopener noreferrer",
            "Install GitHub App ↗",
          )
        } else {
          @html.nothing
        },
      ])
    DeviceAuthorizing(device) => {
      let copy_label = match device.copy_status {
        DeviceCodeCopyReady => "Copy code"
        DeviceCodeCopyDone => "Copied"
        DeviceCodeCopyError(_) => "Try copy again"
      }
      let minutes = (device.expires_in + 59) / 60
      @html.div(class="device-authorization", [
        @html.p("Enter this code on GitHub to finish signing in:"),
        @html.div(class="device-code-row", [
          @html.code(class="device-user-code", device.user_code),
          @html.button(
            type_="button",
            class=if device.copy_status is DeviceCodeCopyDone {
              "secondary device-code-copy copied"
            } else {
              "secondary device-code-copy"
            },
            title=match device.copy_status {
              DeviceCodeCopyError(message) =>
                "Clipboard access failed: \{message}"
              _ => "Copy the GitHub device code"
            },
            on_click=emit(Auth(CopyDeviceCode)),
            copy_label,
          ),
        ]),
        @html.div(class="device-auth-actions", [
          @html.a(
            href=device.verification_uri,
            target=Blank,
            rel="noopener noreferrer",
            "Open GitHub verification page ↗",
          ),
          if device.install_url is Some(url) {
            @html.a(
              href=url,
              target=Blank,
              rel="noopener noreferrer",
              "Install GitHub App ↗",
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            class="secondary",
            on_click=emit(Auth(CancelDeviceAuthorization(device.flow_id))),
            "Cancel",
          ),
        ]),
        @html.p(
          class="device-auth-hint",
          "Waiting for GitHub authorization · expires in about \{minutes} min",
        ),
        match device.copy_status {
          DeviceCodeCopyError(message) =>
            @html.p(
              class="comment-error",
              "Could not copy the code: \{message}",
            )
          _ => @html.nothing
        },
      ])
    }
    DeviceCancelling(_) =>
      @html.span(class="auth-status", "Cancelling GitHub sign-in…")
    AuthFailed(message) =>
      @html.div(class="auth-controls error", [
        @html.span(message),
        @html.button(
          type_="button",
          class="secondary",
          on_click=emit(Auth(StartDeviceAuthorization)),
          "Try sign-in",
        ),
      ])
  }
}

///|
fn comments_overview(
  view : ChangeView,
  review : ReviewState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if review.auth is WebReadOnly {
    return @html.nothing
  }
  let issue_views : Array[@rabbita.Html] = []
  if review.comments is CommentsReady(bundle) {
    for comment in bundle.issue_comments {
      issue_views.push(
        comment_body_view(
          author_label(comment.user),
          comment.created_at,
          comment.body,
          comment.html_url,
        ),
      )
    }
  }
  @html.section(class="comments-overview", [
    @html.div(class="comments-toolbar", [
      @html.div([
        @html.p(class="section-label", "GitHub discussion"),
        @html.h2("Comments"),
      ]),
      @html.div([
        auth_controls(review, emit),
        @html.button(
          type_="button",
          class="secondary refresh-comments",
          disabled=review.comments is CommentsLoading,
          on_click=emit(Review(RefreshComments)),
          "Refresh",
        ),
      ]),
    ]),
    match review.comments {
      CommentsLoading =>
        @html.p(class="comments-loading", "Loading comments…")
      CommentsFailed(message) => @html.p(class="comment-error", message)
      _ => @html.nothing
    },
    if view.reference.target is PullRequest(_) {
      @html.div(class="overall-comments", [
        @html.div(issue_views),
        if review_can_comment(review) {
          if review.draft is Some(draft) && draft.kind is OverallDraft {
            comment_editor(draft, emit)
          } else {
            @html.button(
              type_="button",
              class="secondary add-overall-comment",
              on_click=emit(Review(OpenOverallDraft)),
              "Add overall comment",
            )
          }
        } else {
          @html.nothing
        },
      ])
    } else {
      @html.nothing
    },
  ])
}
