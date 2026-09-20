///|
pub fn get_pull_merge_status(
  args : @protocol.PullMergeStatusGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiPullMergeStatus, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullMergeStatusGet(args),
    generation,
    value => {
      guard value is PullMergeStatus(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn rebase_merge_pull(
  args : @protocol.PullRebaseMerge,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiPullMergeResult, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullRebaseMerge(args),
    generation,
    value => {
      guard value is PullMergeResult(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}
