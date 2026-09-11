///|
async fn App::rpc(
  self : App,
  session : Session?,
  request : @protocol.GitHubRequest,
) -> @protocol.RpcValue {
  match request {
    CommitGet(p) =>
      Commit(
        decode_github(
          self.github_json(
            session,
            "/repos/\{p.owner}/\{p.repo}/commits/\{p.sha}?per_page=100&page=\{p.page}",
          ),
        ),
      )
    PullGet(p) =>
      Pull(
        decode_github(
          self.github_json(
            session,
            "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}",
          ),
        ),
      )
    PullViewedGet(p) =>
      self.with_viewed_scope(session, p, () => {
        PullViewed(self.pull_viewed(session, p))
      })
    PullFileViewedSet(p) =>
      self.with_viewed_scope(
        session,
        { owner: p.owner, repo: p.repo, number: p.number, },
        () => {
          // Keep the coordinator until preflight, mutation and validation finish,
          // even if the browser disconnects. Upstream calls retain their timeout.
          @async.protect_from_cancel(() => {
            FileViewed(self.set_file_viewed(session, p))
          })
        },
      )
    CompareGet(p) =>
      Compare(
        decode_github(
          self.github_json(
            session,
            "/repos/\{p.owner}/\{p.repo}/compare/\{p.base}...\{p.head}",
          ),
        ),
      )
    PullFiles(p) =>
      Files(
        decode_github(
          self.github_json(
            session,
            "/repos/\{p.owner}/\{p.repo}/pulls/\{p.number}/files?per_page=100&page=\{p.page}",
          ),
        ),
      )
    ContentGet(p) => {
      let path = p.path
        .split("/")
        .map(p => encode_component(p.to_owned()))
        .join("/")
      let (response, bytes) = self.github(
        session,
        "/repos/\{p.owner}/\{p.repo}/contents/\{path}?ref=\{p.revision}",
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
      let base = "/repos/\{p.owner}/\{p.repo}"
      match p.target {
        Pull(number~) =>
          Comments({
            issue_comments: decode_github(
              self.comments(session, "\{base}/issues/\{number}/comments"),
            ),
            review_comments: decode_github(
              self.comments(session, "\{base}/pulls/\{number}/comments"),
            ),
            commit_comments: [],
          })
        Commit(sha~) | PullCommit(sha~, ..) =>
          Comments({
            issue_comments: [],
            review_comments: [],
            commit_comments: decode_github(
              self.comments(session, "\{base}/commits/\{sha}/comments"),
            ),
          })
      }
    }
    IssueCommentDelete(p) | ReviewCommentDelete(p) | CommitCommentDelete(p) => {
      guard session is Some(session) && !session.tokens.is_empty() else {
        raise RpcError(
          401, "authentication_required", "Sign in to delete comments.",
        )
      }
      let segment = match request {
        IssueCommentDelete(_) => "issues/comments"
        ReviewCommentDelete(_) => "pulls/comments"
        _ => "comments"
      }
      let path = "/repos/\{p.owner}/\{p.repo}/\{segment}/\{p.comment_id}"
      let comment = self.github_json(Some(session), path)
      guard github_id(field(field(comment, "user"), "id")) == session.user else {
        raise RpcError(
          403, "permission_denied", "You can only delete your own comments.",
        )
      }
      ignore(self.github_json(Some(session), path, meth=Delete))
      Deleted({ deleted: true, })
    }
    IssueCommentCreate(p) =>
      IssueComment(
        decode_github(
          comment_for_protocol(
            self.github_json(
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
        decode_github(
          comment_for_protocol(
            self.github_json(
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
        decode_github(
          comment_for_protocol(
            self.github_json(
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
        decode_github(
          comment_for_protocol(
            self.github_json(
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
