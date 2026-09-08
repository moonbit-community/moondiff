///|
fn run_comment_effect(
  effect : @comments.Effect,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  match effect {
    Notify => @comment_requests.notify_github_page_command()
    Dispatch(event) => emit(Review(Domain(event)))
    CommentsRequest(reference, generation, respond) =>
      @comment_requests.comments_request(reference, generation, result => {
        emit(Review(Domain(respond(result.map_err(comment_failure)))))
      })
    CommentHeadRequest(reference, number, generation, respond) =>
      @comment_requests.comment_head_request(reference, number, generation, result => {
        emit(Review(Domain(respond(result.map_err(comment_failure)))))
      })
    CreateIssueCommentRequest(reference, number, body, generation, respond) =>
      @comment_requests.create_issue_comment_request(
        reference,
        number,
        body,
        generation,
        result => emit(Review(Domain(respond(result.map_err(comment_failure))))),
      )
    CreateReviewCommentRequest(
      reference,
      number,
      commit_id,
      anchor,
      body,
      generation,
      respond
    ) =>
      @comment_requests.create_review_comment_request(
        reference,
        number,
        commit_id,
        anchor,
        body,
        generation,
        result => emit(Review(Domain(respond(result.map_err(comment_failure))))),
      )
    CreateCommitCommentRequest(
      reference,
      sha,
      anchor,
      body,
      generation,
      respond
    ) =>
      @comment_requests.create_commit_comment_request(
        reference,
        sha,
        anchor,
        body,
        generation,
        result => emit(Review(Domain(respond(result.map_err(comment_failure))))),
      )
    CreateReviewReplyRequest(
      reference,
      number,
      comment_id,
      body,
      generation,
      respond
    ) =>
      @comment_requests.create_review_reply_request(
        reference,
        number,
        comment_id,
        body,
        generation,
        result => emit(Review(Domain(respond(result.map_err(comment_failure))))),
      )
    DeleteCommentRequest(reference, id, generation, respond) =>
      @comment_requests.delete_comment_request(reference, id, generation, result => {
        emit(Review(Domain(respond(result.map_err(comment_failure)))))
      })
  }
}
