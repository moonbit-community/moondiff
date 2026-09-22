///|
pub async fn dispatch(
  app : @storage.App,
  session : @storage.Session?,
  request : @protocol.GitHubRequest,
) -> @protocol.RpcValue {
  match request {
    ViewerPullsGet(p) => ViewerPulls(@home.viewer_pulls(app, session, p))
    PullCommitsGet(p) => PullCommits(@home.pull_commits(app, session, p))
    CommitGet(_) =>
      Commit(
        @common.decode_github(
          @github.github_json(app, session, request.public_path().unwrap()),
        ),
      )
    PullGet(_) =>
      Pull(
        @common.decode_github(
          @github.github_json(app, session, request.public_path().unwrap()),
        ),
      )
    PullMergeStatusGet(p) =>
      PullMergeStatus(@merge.pull_merge_status(app, session, p))
    PullRebaseMerge(p) =>
      PullMergeResult(@merge.pull_rebase_merge(app, session, p))
    PullViewedGet(p) =>
      @viewed.with_viewed_scope(app, session, p, () => {
        PullViewed(@viewed.pull_viewed(app, session, p))
      })
    PullFileViewedSet(p) =>
      @viewed.with_viewed_scope(
        app,
        session,
        { owner: p.owner, repo: p.repo, number: p.number, },
        () => {
          // Keep the coordinator until preflight, mutation and validation finish,
          // even if the browser disconnects. Upstream calls retain their timeout.
          @async.protect_from_cancel(() => {
            FileViewed(@viewed.set_file_viewed(app, session, p))
          })
        },
      )
    CompareGet(_) =>
      Compare(
        @common.decode_github(
          @github.github_json(app, session, request.public_path().unwrap()),
        ),
      )
    PullFiles(_) =>
      Files(
        @common.decode_github(
          @github.github_json(app, session, request.public_path().unwrap()),
        ),
      )
    ContentGet(_) => {
      let (response, bytes) = @github.github(
        app,
        session,
        request.public_path().unwrap(),
        source=true,
      )
      Content({
        base64: @base64.encode(bytes),
        size: bytes.length(),
        content_type: response.headers
        .get("Content-Type")
        .unwrap_or("application/octet-stream"),
      })
    }
    CommentsList(p) => {
      let paths = p.public_paths()
      match p.target {
        Pull(_) =>
          Comments({
            issue_comments: @common.decode_github(
              @github.comments(app, session, paths[0]),
            ),
            review_comments: @common.decode_github(
              @github.comments(app, session, paths[1]),
            ),
            commit_comments: [],
          })
        Commit(_) | PullCommit(..) =>
          Comments({
            issue_comments: [],
            review_comments: [],
            commit_comments: @common.decode_github(
              @github.comments(app, session, paths[0]),
            ),
          })
      }
    }
    IssueCommentDelete(p) | ReviewCommentDelete(p) | CommitCommentDelete(p) => {
      guard session is Some(session) && !session.tokens.is_empty() else {
        raise @common.RpcError(
          401, "authentication_required", "Sign in to delete comments.",
        )
      }
      let segment = match request {
        IssueCommentDelete(_) => "issues/comments"
        ReviewCommentDelete(_) => "pulls/comments"
        _ => "comments"
      }
      let path = "/repos/\{p.owner}/\{p.repo}/\{segment}/\{p.comment_id}"
      let comment = @github.github_json(app, Some(session), path)
      guard @common.github_id(
          @common.field(@common.field(comment, "user"), "id"),
        ) ==
        session.user else {
        raise @common.RpcError(
          403, "permission_denied", "You can only delete your own comments.",
        )
      }
      ignore(@github.github_json(app, Some(session), path, meth=Delete))
      Deleted({ deleted: true, })
    }
    IssueCommentCreate(p) =>
      IssueComment(
        @common.decode_github(
          @common.comment_for_protocol(
            @github.github_json(
              app,
              session,
              "/repos/\{p.owner}/\{p.repo}/issues/\{p.number}/comments",
              meth=Post,
              body={ "body": p.body },
            ),
          ),
        ),
      )
    ReviewCommentCreate(p) =>
      ReviewComment(
        @common.decode_github(
          @common.comment_for_protocol(
            @github.github_json(
              app,
              session,
              "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/comments",
              meth=Post,
              body={
                "body": p.body,
                "commit_id": p.commit_id,
                "path": p.path,
                "line": p.line,
                "side": if p.side is Left {
                  "LEFT"
                } else {
                  "RIGHT"
                },
              },
            ),
          ),
        ),
      )
    CommitCommentCreate(p) =>
      CommitComment(
        @common.decode_github(
          @common.comment_for_protocol(
            @github.github_json(
              app,
              session,
              "/repos/\{p.owner}/\{p.repo}/commits/\{p.sha}/comments",
              meth=Post,
              body={ "body": p.body, "path": p.path, "position": p.position },
            ),
          ),
        ),
      )
    ReviewReplyCreate(p) =>
      ReviewComment(
        @common.decode_github(
          @common.comment_for_protocol(
            @github.github_json(
              app,
              session,
              "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/comments/\{p.comment_id}/replies",
              meth=Post,
              body={ "body": p.body },
            ),
          ),
        ),
      )
  }
}
