///|
fn side_from_result(result : Result[(String, Bytes), Error]) -> SideLoad {
  match result {
    Err(error) => LoadFailed(error_message(error, false))
    Ok((_, bytes)) =>
      match check_source(bytes) {
        Renderable(lines) => Ready(lines)
        Rejected(reason, skippable) => CannotRender(reason, skippable)
      }
  }
}
