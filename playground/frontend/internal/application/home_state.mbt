///|
pub(all) enum HomeLoad {
  Unloaded
  Loading
  Paused
  Ready
  Failed(String)
} derive(Eq)

///|
pub(all) struct HomePage[T] {
  items : Array[T]
  total : Int?
  cursor : String?
  load : HomeLoad
  refresh : HomeRefresh[T]?
  updated_at : String?
} derive(Eq)

///|
// Keep a refresh separate from the visible page until its previous depth has
// been fetched. Failed refreshes retain both the visible data and retry cursor.
pub(all) struct HomeRefresh[T] {
  items : Array[T]
  total : Int?
  cursor : String?
  target : Int
  cursor_restarts : Int
} derive(Eq)

///|
pub(all) struct HomeCommits {
  pull : @protocol.ApiPullSummary
  expanded : Bool
  page : HomePage[@protocol.ApiCommitSummary]
  snapshot : (String, String)?
  restarts : Int
} derive(Eq)

///|
pub(all) struct HomeState {
  user : String?
  epoch : Int
  tab : @protocol.ViewerPullKind
  reviews : HomePage[@protocol.ApiPullSummary]
  authored : HomePage[@protocol.ApiPullSummary]
  commits : Map[String, HomeCommits]
} derive(Eq)

///|
fn[T] empty_home_page() -> HomePage[T] {
  {
    items: [],
    total: None,
    cursor: None,
    load: Unloaded,
    refresh: None,
    updated_at: None,
  }
}

///|
fn empty_home_state(epoch : Int) -> HomeState {
  {
    user: None,
    epoch,
    tab: Authored,
    reviews: empty_home_page(),
    authored: empty_home_page(),
    commits: {},
  }
}

///|
pub fn HomeState::new() -> HomeState {
  empty_home_state(0)
}

///|
pub fn home_pull_key(pull : @protocol.ApiPullSummary) -> String {
  "\{pull.owner}/\{pull.repo}/\{pull.number}"
}

///|
fn home_user(auth : AuthStatus) -> String? {
  match auth {
    SignedIn(user_id=Some(id), ..) => Some("id:\{id}")
    SignedIn(login=Some(login), ..) => Some("login:\{login}")
    SignedIn(..) => Some("unknown")
    _ => None
  }
}

///|
fn home_active(model : Model) -> Bool {
  model.route is None && model.phase is Idle && model.auth is SignedIn(..)
}

///|
fn home_list(
  home : HomeState,
  kind : @protocol.ViewerPullKind,
) -> HomePage[@protocol.ApiPullSummary] {
  match kind {
    ReviewRequested => home.reviews
    Authored => home.authored
  }
}

///|
fn with_home_list(
  model : Model,
  kind : @protocol.ViewerPullKind,
  page : HomePage[@protocol.ApiPullSummary],
) -> Model {
  {
    ..model,
    home: match kind {
      ReviewRequested => { ..model.home, reviews: page, }
      Authored => { ..model.home, authored: page, }
    },
  }
}

///|
fn with_home_commits(model : Model, key : String, value : HomeCommits) -> Model {
  let commits = model.home.commits.copy()
  commits[key] = value
  { ..model, home: { ..model.home, commits, }, }
}

///|
fn[T] pause_home_page(page : HomePage[T]) -> HomePage[T] {
  if page.load is Loading {
    { ..page, load: Paused, }
  } else {
    page
  }
}

///|
fn pause_home(home : HomeState) -> HomeState {
  let commits = home.commits.copy()
  for key, value in home.commits {
    commits[key] = { ..value, page: pause_home_page(value.page), }
  }
  {
    ..home,
    epoch: home.epoch + 1,
    reviews: pause_home_page(home.reviews),
    authored: pause_home_page(home.authored),
    commits,
  }
}

///|
fn reconcile_home(
  before : Model,
  next : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  // An invalid URL entered on the anonymous landing page must not keep the
  // old landing shell visible after sign-in. Invalid routes have empty input.
  let next = if !(before.auth is SignedIn(..)) &&
    next.auth is SignedIn(..) &&
    next.route is None &&
    next.phase is LoadFailed(_) &&
    !next.input.is_empty() {
    { ..next, phase: Idle, }
  } else {
    next
  }
  let user = home_user(next.auth)
  let clear = msg is Auth(Logout | StartSignIn) ||
    (
      next.home.user is Some(_) &&
      next.auth
      is (Anonymous(_)
      | AuthFailed(_)
      | Authorizing(_, _)
      | DeviceCancelling(_, _))
    ) ||
    (
      user is Some(_) &&
      user != next.home.user &&
      (home_active(next) || next.home.user is Some(_))
    )
  let mut next = if clear {
    { ..next, home: { ..empty_home_state(next.home.epoch + 1), user, }, }
  } else if next.home.user is Some(_) &&
    (
      before.generation != next.generation ||
      before.auth_revision != next.auth_revision ||
      (home_active(before) && !home_active(next))
    ) {
    { ..next, home: pause_home(next.home), }
  } else {
    next
  }
  guard home_active(next) else { return (next, @rabbita.none) }
  // Generation zero is reserved for session startup. Use scoped requests so
  // navigating away also aborts the very first pair of homepage reads.
  if next.generation == 0 {
    next = { ..next, generation: 1, }
  }
  let commands = []
  for kind in [@protocol.ReviewRequested, Authored] {
    if home_list(next.home, kind).load is (Unloaded | Paused) {
      let (model, command) = begin_home_list(next, kind, emit)
      next = model
      commands.push(command)
    }
  }
  for key, value in next.home.commits {
    if value.expanded && value.page.load is (Unloaded | Paused) {
      let (model, command) = begin_home_commits(next, key, emit)
      next = model
      commands.push(command)
    }
  }
  (next, @rabbita.batch(commands))
}
