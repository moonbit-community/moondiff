///|
priv struct DraftData {
  snapshot : Snapshot?
  id : DraftId
  kind : DraftKind
  body : String
  error : String?
} derive(Eq)

///|
priv struct Operation {
  generation : Int
  id : Int
  phase : SubmissionPhase
  body : String
} derive(Eq)

///|
priv enum EditorState {
  Empty
  Editing(DraftData)
  Submitting(DraftData, Operation)
} derive(Eq)

///|
pub fn Session::draft(self : Session) -> CommentDraft? {
  let (draft, submitting) = match self.editor {
    Empty => return None
    Editing(draft) => (draft, false)
    Submitting(draft, _) => (draft, true)
  }
  Some({
    snapshot: draft.snapshot,
    id: draft.id,
    kind: draft.kind,
    body: draft.body,
    error: draft.error,
    submitting,
  })
}

///|
pub fn Session::submission(self : Session) -> SubmissionPhase? {
  match self.editor {
    Submitting(_, operation) => Some(operation.phase)
    _ => None
  }
}
