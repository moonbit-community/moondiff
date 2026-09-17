///|
pub fn get_viewer_pulls(
  args : @protocol.ViewerPullsGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiViewerPulls, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    ViewerPullsGet(args),
    generation,
    value => {
      guard value is ViewerPulls(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn get_pull_commits(
  args : @protocol.PullCommitsGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiPullCommits, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullCommitsGet(args),
    generation,
    value => {
      guard value is PullCommits(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}
