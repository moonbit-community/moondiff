///|
fn[T] Client::rpc(
  self : Client,
  request : @protocol.GitHubRequest,
  generation : Int,
  select : (@protocol.RpcValue) -> T raise,
  done : (Result[T, Error]) -> Unit,
) -> Unit {
  request.validate() catch {
    error => {
      done(Err(error))
      return
    }
  }
  self.send(
    "/api/rpc",
    request.encode().stringify(),
    result => {
      done(
        match result {
          Err(error) => Err(error)
          Ok(value) =>
            Ok(select(value)) catch {
              _ => Err(invalid_response("Unexpected RPC result kind."))
            }
        },
      )
    },
    generation~,
  )
}

///|
fn[T] rpc_command(
  request : @protocol.GitHubRequest,
  generation : Int,
  select : (@protocol.RpcValue) -> T raise,
  emit : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  command(done => client.rpc(request, generation, select, done), emit)
}

///|
pub fn get_commit(
  args : @protocol.CommitGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiCommit, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    CommitGet(args),
    generation,
    value => {
      guard value is Commit(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn get_pull(
  args : @protocol.PullGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiPull, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullGet(args),
    generation,
    value => {
      guard value is Pull(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn get_compare(
  args : @protocol.CompareGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiCompare, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    CompareGet(args),
    generation,
    value => {
      guard value is Compare(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn get_pull_files(
  args : @protocol.PullFiles,
  generation : Int,
  emit : @rabbita.Emit[Result[Array[@protocol.ApiFile], Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullFiles(args),
    generation,
    value => {
      guard value is Files(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn get_content(
  args : @protocol.ContentGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiSource, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    ContentGet(args),
    generation,
    value => {
      guard value is Content(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn list_comments(
  args : @protocol.CommentsList,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiCommentBundle, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    CommentsList(args),
    generation,
    value => {
      guard value is Comments(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn create_issue_comment(
  args : @protocol.IssueCommentCreate,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiIssueComment, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    IssueCommentCreate(args),
    generation,
    value => {
      guard value is IssueComment(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn create_review_comment(
  args : @protocol.ReviewCommentCreate,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiReviewComment, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    ReviewCommentCreate(args),
    generation,
    value => {
      guard value is ReviewComment(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn create_commit_comment(
  args : @protocol.CommitCommentCreate,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiCommitComment, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    CommitCommentCreate(args),
    generation,
    value => {
      guard value is CommitComment(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn create_review_reply(
  args : @protocol.ReviewReplyCreate,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiReviewComment, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    ReviewReplyCreate(args),
    generation,
    value => {
      guard value is ReviewComment(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn delete_issue_comment(
  args : @protocol.CommentDelete,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.DeleteResult, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    IssueCommentDelete(args),
    generation,
    value => {
      guard value is Deleted(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn delete_review_comment(
  args : @protocol.CommentDelete,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.DeleteResult, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    ReviewCommentDelete(args),
    generation,
    value => {
      guard value is Deleted(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn delete_commit_comment(
  args : @protocol.CommentDelete,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.DeleteResult, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    CommitCommentDelete(args),
    generation,
    value => {
      guard value is Deleted(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn source_request(
  location : SourceLocation,
  generation : Int,
  emit : @rabbita.Emit[Result[(String, Bytes), Error]],
) -> @rabbita.Cmd {
  get_content(
    {
      owner: location.repository.owner,
      repo: location.repository.repo,
      path: location.path,
      revision: location.revision,
    },
    generation,
    result => {
      emit(
        match result {
          Err(error) => Err(error)
          Ok(source) =>
            Ok((source.content_type, source.decode())) catch {
              _ => Err(invalid_response("Invalid source encoding."))
            }
        },
      )
    },
  )
}
