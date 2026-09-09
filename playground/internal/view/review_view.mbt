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
  review : Session,
  anchor : ReviewAnchor?,
) -> CommentDraft? {
  guard review_can_comment(review) &&
    anchor is Some(anchor) &&
    review.draft() is Some(draft) else {
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
  review : Session,
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
        disabled=!@comments.permission(
          review,
          OpenDraft(InlineDraft(file_index, anchor)),
        ).allowed(),
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
  review : Session,
  emit : @rabbita.Emit[Msg],
  unavailable? : Bool = false,
) -> @rabbita.Html {
  @html.div(class="comment-editor", [
    @html.textarea(
      class="comment-textarea",
      value=draft.body,
      rows=4,
      maxlength=65_536,
      placeholder="Leave a comment",
      attrs=@html.Attrs::build().data_set("draft-id", draft.id.key()),
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
        disabled=unavailable || !@comments.permission(review, Submit).allowed(),
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
  review : Session,
  anchor : ReviewAnchor?,
  columns : Int,
  emit : @rabbita.Emit[Msg],
) -> (String, @rabbita.Html) {
  if inline_draft_for_anchor(review, anchor) is Some(draft) &&
    anchor is Some(anchor) {
    (
      draft.id.key(),
      inline_discussion_row(
        "inline-comment-editor-row",
        anchor,
        columns,
        anchor_location(anchor),
        comment_editor(draft, review, emit, unavailable=review.snapshot_stale),
      ),
    )
  } else {
    ("editor:none", @html.nothing)
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
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
  site? : String = "",
) -> Array[(String, @rabbita.Html)] {
  let (old_class, new_class) = review_row_classes(row)
  let cards = inline_cards(
    discussions,
    row.file_index,
    row.old_line,
    row.new_line,
    4,
    site,
  )
  let items : Array[(String, @rabbita.Html)] = [
    (
      source_row_key("split", row.file_index, row.old_line, row.new_line),
      @html.tr(
        class=if cards.is_empty() &&
          inline_draft_for_anchor(review, row.old_anchor) is None &&
          inline_draft_for_anchor(review, row.new_anchor) is None {
          ""
        } else {
          "comment-target"
        },
        [
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
        ],
      ),
    ),
  ]
  items.push_iter(cards.iter())
  if inline_draft_for_anchor(review, row.old_anchor) is Some(_) &&
    projected_editor(discussions, row.old_anchor, row.file_index, site) {
    items.push(inline_editor_row(review, row.old_anchor, 4, emit))
  } else if inline_draft_for_anchor(review, row.new_anchor) is Some(_) &&
    projected_editor(discussions, row.new_anchor, row.file_index, site) {
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
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
  site? : String = "",
) -> Array[(String, @rabbita.Html)] {
  let cards = inline_cards(discussions, file_index, old_line, new_line, 3, site)
  let items : Array[(String, @rabbita.Html)] = [
    (
      source_row_key("unified", file_index, old_line, new_line),
      @html.tr(
        class=if cards.is_empty() &&
          inline_draft_for_anchor(review, anchor) is None {
          ""
        } else {
          "comment-target"
        },
        [
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
        ],
      ),
    ),
  ]
  items.push_iter(cards.iter())
  if inline_draft_for_anchor(review, anchor) is Some(_) &&
    projected_editor(discussions, anchor, file_index, site) {
    items.push(inline_editor_row(review, anchor, 3, emit))
  }
  items
}

///|
fn unified_review_line(
  row : ReviewRow,
  review : Session,
  emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
  site? : String = "",
) -> Array[(String, @rabbita.Html)] {
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
        discussions~,
        site~,
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
          discussions~,
          site~,
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
          discussions~,
          site~,
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
            discussions~,
            site~,
          ).iter(),
        )
        items
      }
    ChangeRow => {
      let items : Array[(String, @rabbita.Html)] = []
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
            discussions~,
            site~,
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
            discussions~,
            site~,
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
  review : Session,
  emit : @rabbita.Emit[Msg],
  old_base? : Int = 0,
  new_base? : Int = 0,
  show_hunk_headers? : Bool = true,
  hunk_context? : String = "",
  fragment? : String = "line",
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  let patch = parse_canonical_patch(file.filename, file.patch)
  let rows : Map[String, @rabbita.Html] = Map([])
  // Count each source identity independently; comments never shift these keys.
  let occurrences : Map[String, Int] = Map([])
  let mut line_index = 0
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
      ReviewHunk(header) => {
        let key = "hunk:\{file_index}:\{old_base}:\{new_base}:\{header}"
        let occurrence = occurrences.get(key).unwrap_or(0)
        occurrences[key] = occurrence + 1
        rows["\{key}:\{occurrence}"] = @html.tr([
          @html.td(
            class="hunk-header",
            colspan=if mode is Split { 4 } else { 3 },
            header,
          ),
        ])
      }
      ReviewLine(row) => {
        // Keep the actual file index even though the gutter only needs the
        // canonical anchor. This makes the selected draft stable across views.
        let row = { ..row, file_index, }
        let rendered = match mode {
          Split =>
            split_review_line(
              row,
              review,
              emit,
              discussions~,
              site=projection_site(
                file_index, old_base, new_base, line_index, fragment,
              ),
            )
          Unified =>
            unified_review_line(
              row,
              review,
              emit,
              discussions~,
              site=projection_site(
                file_index, old_base, new_base, line_index, fragment,
              ),
            )
        }
        line_index += 1
        for (key, node) in rendered {
          let occurrence = occurrences.get(key).unwrap_or(0)
          occurrences[key] = occurrence + 1
          rows["\{key}:\{occurrence}"] = node
        }
      }
    }
  }
  @html.div(class="diff-scroll review-scroll", [
    @html.table(
      class=if mode is Split {
        "split review-diff"
      } else {
        "unified numbered review-diff"
      },
      [
        @html.colgroup(
          if mode is Split {
            [
              @html.col(class="gutter-column"),
              @html.col(),
              @html.col(class="gutter-column"),
              @html.col(),
            ]
          } else {
            [
              @html.col(class="gutter-column"),
              @html.col(class="gutter-column"),
              @html.col(),
            ]
          },
        ),
        @html.tbody(rows),
      ],
    ),
  ])
}

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
    comment_delete_controls(id, review, emit),
  ])
}

///|
fn review_thread_view(
  thread : ReviewThread,
  review : Session,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let can_comment = review_can_comment(review)
  let comments : Map[String, @rabbita.Html] = Map([])
  comments[review.comment_key(ReviewComment(thread.root.id))] = comment_body_view(
    author_label(thread.root.user),
    thread.root.created_at,
    thread.root.body,
    thread.root.html_url,
    ReviewComment(thread.root.id),
    review,
    emit,
  )
  for reply in thread.replies {
    comments[review.comment_key(ReviewComment(reply.id))] = comment_body_view(
      author_label(reply.user),
      reply.created_at,
      reply.body,
      reply.html_url,
      ReviewComment(reply.id),
      review,
      emit,
    )
  }
  if can_comment {
    comments["reply-control"] = @html.button(
      type_="button",
      class="comment-reply-button",
      disabled=!@comments.permission(
        review,
        OpenDraft(ReplyDraft(thread.root.id)),
      ).allowed(),
      title=if thread.root.in_reply_to_id is Some(_) {
        "The root comment has been deleted."
      } else if !@comments.valid_reply_target(review, thread.root.id) {
        "The root comment is unavailable or being deleted."
      } else {
        "Reply to this thread"
      },
      on_click=emit(Review(OpenReplyDraft(thread.root.id))),
      "Reply",
    )
  }
  if can_comment &&
    review.draft() is Some(draft) &&
    draft.kind is ReplyDraft(id) &&
    id == thread.root.id &&
    @comments.valid_reply_target(review, id) {
    comments[draft.id.key()] = comment_editor(draft, review, emit)
  }
  @html.div(class="review-thread", comments)
}

///|
fn file_discussions_view(
  _view : ChangeView,
  file_index : Int,
  _review : Session,
  _emit : @rabbita.Emit[Msg],
  discussions? : InlineDiscussions = empty_discussions(),
) -> @rabbita.Html {
  fallback_discussions(discussions, Some(file_index))
}

///|
fn auth_controls(
  auth : @application.AuthStatus,
  emit : @rabbita.Emit[Msg],
  refresh? : @rabbita.Html = @html.nothing,
) -> @rabbita.Html {
  match auth {
    WebReadOnly => @html.nothing
    AuthChecking =>
      @html.span(class="auth-status", "Checking GitHub session…")
    SignedIn(login~, install_url~) =>
      @html.div(class="auth-controls", [
        @html.span("Signed in\{login.map(name => " as \{name}").unwrap_or("")}"),
        refresh,
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
  review : Session,
  auth : @application.AuthStatus,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if auth is WebReadOnly {
    return @html.nothing
  }
  let refresh = @html.button(
    type_="button",
    class="secondary refresh-comments",
    disabled=!(review.refresh() is RefreshIdle),
    on_click=emit(Review(RefreshComments)),
    "Refresh",
  )
  let issue_views : Map[String, @rabbita.Html] = Map([])
  if review.comments() is CommentsReady(bundle) {
    for comment in bundle.issue_comments {
      issue_views[review.comment_key(IssueComment(comment.id))] = comment_body_view(
        author_label(comment.user),
        comment.created_at,
        comment.body,
        comment.html_url,
        IssueComment(comment.id),
        review,
        emit,
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
        auth_controls(auth, emit, refresh~),
        if auth is SignedIn(_) {
          @html.nothing
        } else {
          refresh
        },
      ]),
    ]),
    if review.snapshot_stale {
      @html.div(class="snapshot-stale", [
        @html.p("PR updated. Load the latest snapshot to comment on new lines."),
        @html.button(
          type_="button",
          class="secondary load-latest-snapshot",
          disabled=!@comments.permission(review, LoadSnapshot).allowed(),
          on_click=emit(Review(LoadLatestSnapshot)),
          "Load latest",
        ),
      ])
    } else {
      @html.nothing
    },
    if review.notice is Some(message) {
      @html.p(class="comment-notice", message)
    } else {
      @html.nothing
    },
    if review.published_url is Some(url) {
      @html.a(
        class="published-comment-link",
        href=url,
        target=Blank,
        rel="noopener noreferrer",
        "View published comment on GitHub ↗",
      )
    } else {
      @html.nothing
    },
    if review.refresh_error is Some(message) &&
      review.comments() is CommentsReady(_) {
      @html.p(class="comment-error", message)
    } else {
      @html.nothing
    },
    match review.comments() {
      CommentsLoading =>
        if review.snapshot_stale {
          @html.nothing
        } else {
          @html.p(class="comments-loading", "Loading comments…")
        }
      CommentsFailed(message) => @html.p(class="comment-error", message)
      _ => @html.nothing
    },
    fallback_discussions(prepare_discussions(view, review, emit), None),
    if review_can_comment(review) &&
      review.draft() is Some(draft) &&
      draft.kind is ReplyDraft(id) &&
      !@comments.valid_reply_target(review, id) {
      @html.div(class="unavailable-reply-draft", [
        @html.p(
          "The root comment is unavailable. Your reply draft is preserved; copy its text or cancel it.",
        ),
        comment_editor(draft, review, emit, unavailable=true),
      ])
    } else {
      @html.nothing
    },
    if view.reference.target is PullRequest(_) {
      @html.div(class="overall-comments", [
        @html.div(issue_views),
        if review_can_comment(review) {
          if review.draft() is Some(draft) && draft.kind is OverallDraft {
            comment_editor(draft, review, emit)
          } else {
            @html.button(
              type_="button",
              class="secondary add-overall-comment",
              disabled=!@comments.permission(review, OpenDraft(OverallDraft)).allowed(),
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

///|
fn source_row_key(
  layout : String,
  file_index : Int,
  old_line : Int?,
  new_line : Int?,
) -> String {
  "source:\{layout}:\{file_index}:\{old_line.map(n => n.to_string()).unwrap_or("-")}:\{new_line.map(n => n.to_string()).unwrap_or("-")}"
}
