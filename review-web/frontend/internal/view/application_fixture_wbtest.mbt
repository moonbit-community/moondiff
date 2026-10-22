///|
fn[T] test_home_page() -> @application.HomePage[T] {
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
fn test_home_state() -> @application.HomeState {
  {
    user: None,
    epoch: 0,
    tab: Authored,
    reviews: test_home_page(),
    authored: test_home_page(),
    commits: {},
  }
}

///|
fn test_viewed_state() -> @application.ViewedState {
  {
    user_id: None,
    epoch: 0,
    serial: 0,
    read_serial: 0,
    files: [],
    loading: false,
    ready: false,
    refresh_needed: false,
    error: None,
    stale: false,
    storage_ready: false,
    retry: 0,
    poll_scheduled: false,
  }
}

///|
fn test_pull_merge_state() -> @application.PullMergeState {
  {
    epoch: 0,
    serial: 0,
    status: None,
    loading: false,
    submitting: false,
    error: None,
    retry: 0,
    poll_scheduled: false,
    stale: false,
  }
}
