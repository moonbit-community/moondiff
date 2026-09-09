///|
const INTERRUPTED_REQUEST_MESSAGE : String = "请求已中断，结果尚未确认，请检查后再重试"

///|
fn recover_interrupted(session : Session) -> Session {
  let interrupted = session.editor is Submitting(_, _) ||
    session.deletion is Some(Deleting(_))
  {
    ..session,
    submission_id: session.submission_id + 1,
    deletion_id: session.deletion_id + 1,
    refresh_id: session.refresh_id + 1,
    refresh: RefreshIdle,
    editor: match session.editor {
      Submitting(draft, _) =>
        Editing({ ..draft, error: Some(INTERRUPTED_REQUEST_MESSAGE), })
      other => other
    },
    deletion: match session.deletion {
      Some(Deleting(id)) => Some(DeleteFailed(id, INTERRUPTED_REQUEST_MESSAGE))
      other => other
    },
    notice: if interrupted {
      Some(INTERRUPTED_REQUEST_MESSAGE)
    } else {
      session.notice
    },
  }
}
