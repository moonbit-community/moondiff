///|
pub(all) enum SignInEntry {
  Comment(Int32)
  Viewed(Int32)
} derive(Eq)

///|
pub fn SignInEntry::file_index(self : SignInEntry) -> Int32 {
  match self {
    Comment(index) | Viewed(index) => index
  }
}

///|
pub(all) struct SignInDialog {
  revision : Int32
  entry : SignInEntry?
} derive(Eq)

///|
pub fn SignInDialog::new() -> SignInDialog {
  { revision: 0, entry: None, }
}

///|
fn reconcile_sign_in_dialog(before : Model, next : Model) -> Model {
  if next.sign_in_dialog.entry is Some(_) &&
    (
      before.generation != next.generation ||
      next.auth is SignedIn(..) ||
      !(next.phase is Showing({ reference: { target: PullRequest(_), .. }, .. }))
    ) {
    {
      ..next,
      sign_in_dialog: {
        revision: next.sign_in_dialog.revision + 1,
        entry: None,
      },
    }
  } else {
    next
  }
}
