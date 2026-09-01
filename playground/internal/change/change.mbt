///|
pub fn initial_side(url : String?, expanded : Bool) -> SideLoad {
  if url is Some(_) {
    if expanded {
      Loading
    } else {
      NotRequested
    }
  } else {
    Ready([])
  }
}

///|
pub fn source_requests_for_file(
  view : ChangeView,
  index : Int,
) -> Array[(SourceSide, SourceLocation)] {
  guard view.files.get(index) is Some(state) else { return [] }
  let pair = source_pair_for_revisions(
    view.old_revision,
    view.new_revision,
    state.file,
  )
  let requests : Array[(SourceSide, SourceLocation)] = []
  if pair.old_location is Some(location) {
    requests.push((Old, location))
  }
  if pair.new_location is Some(location) {
    requests.push((New, location))
  }
  requests
}

///|
pub fn finish_change(
  reference : CommitRef,
  old_revision : Revision?,
  new_revision : Revision,
  message : String,
  html_url : String,
  stats : ApiStats,
  all_files : Array[ApiFile],
) -> ChangeView {
  let states : Array[FileState] = []
  let mut moonbit_file_count = 0
  for file in all_files {
    let diff_mode = file_diff_mode(file)
    let expanded = diff_mode is MoonBitDiff && moonbit_file_count < 20
    if diff_mode is MoonBitDiff {
      moonbit_file_count += 1
    }
    let pair = source_pair_for_revisions(old_revision, new_revision, file)
    states.push({
      file,
      diff_mode,
      expanded,
      old_side: initial_side(pair.old_url, expanded),
      new_side: initial_side(pair.new_url, expanded),
      diff_cache: DiffCache::empty(),
    })
  }
  {
    reference,
    sha: new_revision.sha,
    parent_sha: old_revision.map(revision => revision.sha),
    old_revision,
    new_revision,
    message,
    html_url,
    stats,
    total_files: all_files.length(),
    files: states,
  }
}

///|
pub fn finish_commit(
  reference : CommitRef,
  repository : RepositoryRef,
  first : ApiCommit,
  all_files : Array[ApiFile],
) -> ChangeView {
  let (old_revision, new_revision) = repository_commit_revisions(
    repository,
    first.sha,
    first_parent(first),
  )
  finish_change(
    reference,
    old_revision,
    new_revision,
    first.commit.message,
    first.html_url,
    first.stats,
    all_files,
  )
}

///|
pub fn finish_pull(
  reference : CommitRef,
  pull : ApiPull,
  compare : ApiCompare,
  all_files : Array[ApiFile],
) -> Result[ChangeView, String] {
  match validate_pull_files(pull, all_files) {
    Err(message) => Err(message)
    Ok(_) => {
      let (old_revision, new_revision) = pull_revisions(
        reference, pull, compare,
      )
      Ok(
        finish_change(
          reference,
          old_revision,
          new_revision,
          pull.title,
          pull.html_url,
          pull_stats(pull),
          all_files,
        ),
      )
    }
  }
}

///|
pub fn set_file_state(
  view : ChangeView,
  index : Int,
  state : FileState,
) -> ChangeView {
  let files = view.files.copy()
  files[index] = state
  { ..view, files, }
}
