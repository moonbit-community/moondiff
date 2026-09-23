///|
pub(all) struct RangeState {
  from_sha : String
  to_sha : String
  base_sha : String
  head_sha : String
  commits : Array[@protocol.ApiRangeCommit]
  linear_commits : Array[@protocol.ApiRangeCommit]?
  total_commits : Int
  loading_page : Int?
  next_page : Int?
  error : String?
  expanded : Bool
  comparison : @protocol.ApiRangeCompare?
  pull : ApiPull?
  pull_merge_base : String?
  too_many_files : Bool
} derive(Eq)

///|
fn range_state(base : String, head : String, pull : ApiPull?) -> RangeState {
  {
    from_sha: base,
    to_sha: head,
    base_sha: base,
    head_sha: head,
    commits: [],
    linear_commits: None,
    total_commits: 0,
    loading_page: Some(1),
    next_page: None,
    error: None,
    expanded: false,
    comparison: None,
    pull,
    pull_merge_base: None,
    too_many_files: false,
  }
}

///|
fn range_reference_parts(reference : CommitRef) -> (String, String)? {
  match reference.target {
    Range(base, head) | PullRange(_, base, head) => Some((base, head))
    _ => None
  }
}

///|
fn range_full_sha(sha : String) -> Bool {
  (sha.length() == 40 || sha.length() == 64) && @github.valid_sha(sha)
}

///|
fn pull_linear_chain(
  base : String,
  head : String,
  commits : Array[@protocol.ApiRangeCommit],
) -> Array[@protocol.ApiRangeCommit]? {
  if !range_full_sha(base) || !range_full_sha(head) {
    return None
  }
  let by_sha : Map[String, @protocol.ApiRangeCommit] = Map([])
  for commit in commits {
    let sha = commit.sha.to_lower()
    if !range_full_sha(commit.sha) || by_sha.get(sha) is Some(_) {
      return None
    }
    by_sha[sha] = commit
  }
  let reversed : Array[@protocol.ApiRangeCommit] = []
  let base = base.to_lower()
  let mut current = head.to_lower()
  while current != base {
    guard by_sha.get(current) is Some(commit) && commit.parents.length() == 1 else {
      return None
    }
    let parent = commit.parents[0].sha
    if !range_full_sha(parent) {
      return None
    }
    reversed.push(commit)
    if reversed.length() > commits.length() {
      return None
    }
    current = parent.to_lower()
  }
  if reversed.length() != commits.length() {
    return None
  }
  let ordered : Array[@protocol.ApiRangeCommit] = []
  for i in 0..<reversed.length() {
    ordered.push(reversed[reversed.length() - i - 1])
  }
  Some(ordered)
}

///|
pub fn range_pull_selector_ready(state : RangeState) -> Bool {
  state.linear_commits is Some(commits) &&
  !commits.is_empty() &&
  state.loading_page is None &&
  state.next_page is None &&
  state.error is None
}

///|
pub fn range_pull_history_unsupported(state : RangeState) -> Bool {
  state.pull is Some(_) &&
  state.total_commits > 0 &&
  state.loading_page is None &&
  state.next_page is None &&
  state.error is None &&
  state.linear_commits is None
}

///|
fn range_commit_position(state : RangeState, sha : String) -> Int? {
  if sha == state.base_sha {
    return Some(0)
  }
  let mut position = 1
  let commits = state.linear_commits.unwrap_or(state.commits)
  for commit in commits {
    if commit.sha != state.base_sha {
      if commit.sha == sha {
        return Some(position)
      }
      position += 1
    }
  }
  if sha == state.head_sha && state.head_sha != state.base_sha {
    Some(position)
  } else {
    None
  }
}

///|
pub fn range_commit_after(
  state : RangeState,
  from_sha : String,
  to_sha : String,
) -> Bool {
  match
    (
      range_commit_position(state, from_sha),
      range_commit_position(state, to_sha),
    ) {
    (Some(from), Some(to)) => to > from
    _ => false
  }
}

///|
fn range_page_error(
  state : RangeState,
  page : Int,
  data : @protocol.ApiRangeCompare,
) -> String? {
  let base = data.base_commit.sha
  if !range_full_sha(base) ||
    !range_full_sha(state.head_sha) ||
    base.to_lower() != state.base_sha.to_lower() ||
    !range_full_sha(data.merge_base_commit.sha) {
    return Some(
      "GitHub returned different comparison endpoints. Reload this interval.",
    )
  }
  if data.merge_base_commit.sha.to_lower() != base.to_lower() {
    return Some(
      "These endpoints do not form a supported commit interval: the start must be an ancestor of the end.",
    )
  }
  if data.total_commits < 0 ||
    (data.total_commits == 0) !=
    (state.base_sha.to_lower() == state.head_sha.to_lower()) ||
    data.commits.length() > 100 ||
    data.total_commits < data.commits.length() ||
    data.commits.length() !=
    Int::min(100, data.total_commits - state.commits.length()) {
    return Some("GitHub returned an invalid commit interval page.")
  }
  if page == 1 && data.files is None {
    return Some("GitHub did not return the changed files for this interval.")
  }
  if page > 1 &&
    (
      base != state.base_sha ||
      data.total_commits != state.total_commits ||
      data.commits.is_empty()
    ) {
    return Some("GitHub returned an inconsistent commit interval page.")
  }
  for commit in data.commits {
    if !range_full_sha(commit.sha) ||
      state.commits
      .iter()
      .any(previous => previous.sha.to_lower() == commit.sha.to_lower()) {
      return Some("GitHub returned an invalid commit SHA.")
    }
  }
  for index, commit in data.commits {
    for previous in data.commits[:index] {
      if previous.sha.to_lower() == commit.sha.to_lower() {
        return Some("GitHub returned duplicate commits.")
      }
    }
  }
  if state.commits.length() + data.commits.length() == data.total_commits &&
    data.total_commits > 0 &&
    data.commits[data.commits.length() - 1].sha.to_lower() !=
    state.head_sha.to_lower() {
    return Some("GitHub returned a different final commit for this interval.")
  }
  None
}

///|
fn accept_range_page(
  state : RangeState,
  page : Int,
  data : @protocol.ApiRangeCompare,
) -> RangeState {
  let commits = state.commits.copy()
  for commit in data.commits {
    commits.push(commit)
  }
  let base_sha = data.base_commit.sha
  let linear_commits = if commits.length() == data.total_commits {
    pull_linear_chain(base_sha, state.head_sha, commits)
  } else {
    None
  }
  {
    ..state,
    base_sha,
    from_sha: if page == 1 && state.from_sha == state.base_sha {
      base_sha
    } else {
      state.from_sha
    },
    commits,
    linear_commits,
    total_commits: data.total_commits,
    loading_page: None,
    next_page: if commits.length() < data.total_commits {
      Some(page + 1)
    } else {
      None
    },
    error: None,
    comparison: if page == 1 {
      Some(data)
    } else {
      state.comparison
    },
    too_many_files: if page == 1 {
      data.files.map(files => files.length() >= 300).unwrap_or(false)
    } else {
      state.too_many_files
    },
  }
}
