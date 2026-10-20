///|
fn home_prefetch_candidates(
  model : Model,
) -> Array[@github_client.PrefetchCandidate] {
  let selected : Array[@github_client.PrefetchCandidate] = []
  let seen : Map[String, Bool] = Map([])
  for pull in home_list(model.home, model.home.tab).items {
    let key = home_pull_key(pull).to_lower()
    if !seen.contains(key) {
      seen[key] = true
      selected.push({
        pull: { owner: pull.owner, repo: pull.repo, number: pull.number, },
        updated_at: pull.updated_at,
      })
      if selected.length() == 5 {
        break
      }
    }
  }
  selected
}

///|
fn prefetch_eligible(model : Model) -> Bool {
  home_active(model) &&
  !model.access.identity_checking &&
  model.auth is SignedIn(user_id=Some(_), ..) &&
  model.page_visible
}

///|
fn prefetch_after_commit(before : Model, next : Model) -> AfterCommit? {
  guard prefetch_eligible(next) &&
    (
      !prefetch_eligible(before) ||
      home_prefetch_candidates(before) != home_prefetch_candidates(next) ||
      before.home.epoch != next.home.epoch
    ) else {
    return None
  }
  Some({
    target: Home,
    scope: Region,
    navigation: Cancel,
    command: @github_client.prefetch_home(
      home_prefetch_candidates(next),
      next.home.epoch,
    ),
  })
}

///|
fn leave_home_prefetch(before : Model, next : Model) -> @rabbita.Cmd {
  if before.page_visible && !next.page_visible {
    return @github_client.stop_prefetch()
  }
  // The target PR command attaches/promotes before releasing the homepage.
  if prefetch_eligible(before) &&
    !prefetch_eligible(next) &&
    !(next.route
    .map(reference => reference.target is PullRequest(_))
    .unwrap_or(false) &&
    next.phase is LoadingPullMetadata(..)) {
    @github_client.stop_prefetch()
  } else {
    @rabbita.none
  }
}
