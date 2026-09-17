///|
extern "js" fn home_now() -> String =
  #| () => new Date().toISOString()

///|
fn[T] home_pending(page : HomePage[T]) -> Bool {
  page.load is (Unloaded | Loading | Paused)
}

///|
pub fn HomeState::busy(self : HomeState) -> Bool {
  home_pending(self.reviews) ||
  home_pending(self.authored) ||
  self.commits
  .values()
  .any(value => {
    value.expanded && value.page.refresh is Some(_) && home_pending(value.page)
  })
}

///|
fn[T] refresh_home_page(page : HomePage[T]) -> HomePage[T] {
  {
    ..page,
    load: Unloaded,
    refresh: Some({
      items: [],
      total: None,
      cursor: None,
      target: page.items.length(),
      cursor_restarts: 0,
    }),
  }
}

///|
fn[T] home_cursor(page : HomePage[T]) -> String? {
  match page.refresh {
    Some(refresh) => refresh.cursor
    None => page.cursor
  }
}

///|
fn[T] home_items(page : HomePage[T]) -> Array[T] {
  match page.refresh {
    Some(refresh) => refresh.items
    None => page.items
  }
}

///|
fn[T] restart_home_page(page : HomePage[T]) -> HomePage[T] {
  if page.refresh is Some(refresh) {
    {
      ..page,
      load: Unloaded,
      refresh: Some({ ..refresh, items: [], total: None, cursor: None, }),
    }
  } else {
    { ..empty_home_page(), updated_at: page.updated_at, }
  }
}

///|
fn[T] recover_home_cursor(page : HomePage[T], error : Error) -> HomePage[T] {
  let restarted = restart_home_page(page)
  if restarted.refresh is Some(refresh) {
    {
      ..restarted,
      load: if refresh.cursor_restarts == 0 {
        Unloaded
      } else {
        Failed(home_failure_message(error))
      },
      refresh: Some({ ..refresh, cursor_restarts: refresh.cursor_restarts + 1, }),
    }
  } else {
    restarted
  }
}

///|
fn[T] receive_home_page(
  previous : HomePage[T],
  items : Array[T],
  total : Int,
  cursor : String?,
  incomplete? : String,
) -> HomePage[T] {
  let load = match incomplete {
    Some(message) => Failed(message)
    None => Ready
  }
  if previous.refresh is Some(refresh) {
    if incomplete is Some(_) ||
      (items.length() < refresh.target && cursor is Some(_)) {
      return {
        ..previous,
        load: if incomplete is Some(_) {
          load
        } else {
          Unloaded
        },
        refresh: Some({ ..refresh, items, total: Some(total), cursor, }),
      }
    }
  }
  {
    items,
    total: Some(total),
    cursor,
    load,
    refresh: None,
    updated_at: if incomplete is None &&
      (previous.updated_at is None || previous.refresh is Some(_)) {
      Some(home_now())
    } else {
      previous.updated_at
    },
  }
}

///|
fn refresh_home(home : HomeState) -> HomeState {
  let commits = home.commits.copy()
  for key, value in home.commits {
    commits[key] = {
      ..value,
      page: refresh_home_page(value.page),
      snapshot: None,
      restarts: 0,
    }
  }
  {
    ..home,
    epoch: home.epoch + 1,
    reviews: refresh_home_page(home.reviews),
    authored: refresh_home_page(home.authored),
    commits,
  }
}

///|
fn prune_home_commits(model : Model) -> Model {
  let visible : Map[String, Bool] = Map([])
  for page in [model.home.reviews, model.home.authored] {
    for pull in page.items {
      visible[home_pull_key(pull)] = true
    }
  }
  let commits = model.home.commits.copy()
  for key, _ in model.home.commits {
    if !visible.contains(key) {
      commits.remove(key)
    }
  }
  { ..model, home: { ..model.home, commits, }, }
}
