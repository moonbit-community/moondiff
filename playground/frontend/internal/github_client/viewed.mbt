///|
pub fn get_pull_viewed(
  args : @protocol.PullViewedGet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiPullViewed, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullViewedGet(args),
    generation,
    value => {
      guard value is PullViewed(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}

///|
pub fn set_file_viewed(
  args : @protocol.PullFileViewedSet,
  generation : Int,
  emit : @rabbita.Emit[Result[@protocol.ApiFileViewedResult, Error]],
) -> @rabbita.Cmd {
  rpc_command(
    PullFileViewedSet(args),
    generation,
    value => {
      guard value is FileViewed(data) else {
        raise invalid_response("Unexpected RPC result kind.")
      }
      data
    },
    emit,
  )
}
