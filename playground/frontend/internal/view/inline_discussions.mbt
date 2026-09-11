///|
priv struct InlineDiscussion {
  id : @comments.CommentId
  file_index : Int?
  anchor : ReviewAnchor?
  location : String
  outdated : Bool
  content : @rabbita.Html
}

///|
// Render-local data: one absolute-line index and a precomputed placement map,
// shared across the file fragments.
priv struct InlineDiscussions {
  generation : Int
  items : Array[InlineDiscussion]
  projection : ReviewProjection
  index : Map[String, Array[InlineDiscussion]]
  draft_file_index : Int?
  draft : CommentDraft?
  editor : @rabbita.Html
}

///|
fn empty_discussions() -> InlineDiscussions {
  {
    generation: 0,
    items: [],
    projection: { lines: Map([]), editors: Map([]), },
    index: {},
    draft_file_index: None,
    draft: None,
    editor: @html.nothing,
  }
}

///|
fn anchor_location(anchor : ReviewAnchor) -> String {
  let side = if anchor.side is Left { "Old" } else { "New" }
  "\{anchor.path} · \{side} · \{anchor.line}"
}

///|
fn prepare_discussions(
  view : ChangeView,
  review : Session,
  emit : @rabbita.Emit[Msg],
  projection? : ReviewProjection = { lines: Map([]), editors: Map([]), },
) -> InlineDiscussions {
  let result = {
    ..empty_discussions(),
    generation: review.generation(),
    projection,
    draft: review.draft(),
    draft_file_index: match review.draft() {
      Some({ kind: InlineDraft(_, anchor), .. }) => {
        let mut found = None
        for index, file in view.files {
          if file.file.filename == anchor.path {
            found = Some(index)
            break
          }
        }
        found
      }
      _ => None
    },
    editor: if review.draft() is Some(draft) && review.draft_visible() {
      comment_editor(
        draft,
        review,
        emit,
        unavailable=review.snapshot_stale && draft.kind is InlineDraft(_, _),
      )
    } else {
      @html.nothing
    },
  }
  guard review.comments() is CommentsReady(bundle) else { return result }
  for thread in review_threads(view, bundle.review_comments) {
    let root = thread.root
    let side : @review.ReviewSide = if root.side == Some(@protocol.Left) {
      Left
    } else {
      Right
    }
    let line = if thread.outdated && root.original_line is Some(_) {
      root.original_line
    } else {
      root.line
    }
    let anchor = if !thread.outdated &&
      root.line is Some(line) &&
      thread.file_index is Some(index) {
      @review.canonical_anchor(
        parse_canonical_patch(root.path, view.files[index].file.patch),
        side,
        line,
      )
    } else {
      None
    }
    let location = if line is Some(line) {
      anchor_location({ path: root.path, side, line, position: root.position, })
    } else {
      root.path + " · Line unavailable"
    }
    result.items.push({
      id: thread.id,
      file_index: thread.file_index,
      anchor,
      location,
      outdated: thread.outdated,
      content: review_thread_view(thread, review, emit),
    })
  }
  for discussion in commit_discussions(view, bundle.commit_comments) {
    let comment = discussion.comment
    let anchor = if discussion.file_index is Some(index) &&
      comment.position is Some(position) &&
      parse_canonical_patch(
        view.files[index].file.filename,
        view.files[index].file.patch,
      )
      is Commentable(anchors) {
      anchors.iter().find_first(a => a.position == Some(position))
    } else {
      None
    }
    let location = anchor
      .map(anchor_location)
      .unwrap_or(
        comment.path.unwrap_or("General discussion") +
        " · " +
        comment.line.map(n => "Line \{n}").unwrap_or("Line unavailable"),
      )
    result.items.push({
      id: CommitComment(comment.id),
      file_index: discussion.file_index,
      anchor,
      location,
      outdated: discussion.outdated && comment.path is Some(_),
      content: comment_body_view(
        author_label(comment.user),
        comment.created_at,
        comment.body,
        comment.html_url,
        CommitComment(comment.id),
        review,
        emit,
      ),
    })
  }
  for item in result.items {
    if item.file_index is Some(file_index) && item.anchor is Some(anchor) {
      let key = discussion_key(file_index, anchor.side, anchor.line)
      match result.index.get(key) {
        Some(items) => items.push(item)
        None => result.index[key] = [item]
      }
    }
  }
  result
}

///|
fn inline_cards(
  discussions : InlineDiscussions,
  file_index : Int,
  old_line : Int?,
  new_line : Int?,
  columns : Int,
  site : String,
) -> Array[(String, @rabbita.Html)] {
  let cards : Array[(String, @rabbita.Html)] = []
  let matching : Array[InlineDiscussion] = []
  if old_line is Some(line) {
    matching.push_iter(
      discussions.index
      .get(discussion_key(file_index, Left, line))
      .unwrap_or([])
      .iter(),
    )
  }
  if new_line is Some(line) {
    matching.push_iter(
      discussions.index
      .get(discussion_key(file_index, Right, line))
      .unwrap_or([])
      .iter(),
    )
  }
  for item in matching {
    guard item.file_index == Some(file_index) && item.anchor is Some(anchor) else {
      continue
    }
    let line = if anchor.side is Left { old_line } else { new_line }
    if line == Some(anchor.line) &&
      discussions.projection.lines.get(
        discussion_key(file_index, anchor.side, anchor.line),
      ) ==
      Some(site) {
      let key = "\{discussions.generation}:\{item.id.key()}"
      cards.push(
        (
          key,
          inline_discussion_row(
            "inline-discussion-row",
            anchor,
            columns,
            item.location,
            item.content,
          ),
        ),
      )
    }
  }
  cards
}

///|
fn inline_discussion_row(
  class_name : String,
  anchor : ReviewAnchor,
  columns : Int,
  location : String,
  content : @rabbita.Html,
) -> @rabbita.Html {
  @html.tr(class=class_name, [
    @html.td(colspan=columns, [
      @html.div(
        class=if anchor.side is Left {
          "inline-discussion inline-left"
        } else {
          "inline-discussion inline-right"
        },
        [@html.p(class="comment-location", location), content],
      ),
    ]),
  ])
}

///|
fn fallback_discussions(
  discussions : InlineDiscussions,
  file_index : Int?,
) -> @rabbita.Html {
  let items : Map[String, @rabbita.Html] = Map([])
  for item in discussions.items {
    if item.file_index == file_index &&
      !item.anchor
      .map(a => {
        discussions.projection.lines.contains(
          discussion_key(file_index.unwrap_or(-1), a.side, a.line),
        )
      })
      .unwrap_or(false) {
      items["\{discussions.generation}:\{item.id.key()}"] = @html.div(
        class=if item.outdated {
          "outdated-discussions"
        } else {
          "active-discussions"
        },
        [
          @html.p(
            class="comment-location",
            item.location +
            (if item.outdated {
              " · Outdated"
            } else {
              " · Not shown in current view"
            }),
          ),
          item.content,
        ],
      )
    }
  }
  if discussions.draft is Some(draft) &&
    draft.kind is InlineDraft(_, anchor) &&
    file_index == discussions.draft_file_index &&
    !discussions.projection.editors.contains(
      discussion_key(file_index.unwrap_or(-1), anchor.side, anchor.line),
    ) {
    items[draft.id.key()] = @html.div([
      @html.p(
        class="comment-location",
        anchor_location(anchor) + " · Not shown in current view",
      ),
      discussions.editor,
    ])
  }
  if items.is_empty() {
    @html.nothing
  } else {
    @html.section(class="file-discussions", items)
  }
}

///|
fn discussion_key(
  file_index : Int,
  side : @review.ReviewSide,
  line : Int,
) -> String {
  let side = if side is Left { "L" } else { "R" }
  "\{file_index}:\{side}:\{line}"
}
