///|
fn commit_request(
  reference : CommitRef,
  repository : RepositoryRef,
  generation : Int,
  page : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let sha = match reference.target {
    Commit(sha) | PullCommit(_, sha) => sha
    PullRequest(_) => ""
  }
  @github_client.get_commit(
    { owner: repository.owner, repo: repository.repo, sha, page, },
    generation,
    result => emit(Load(CommitPageLoaded(generation, page, result))),
  )
}

///|
fn pull_commit_metadata_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullCommit(number, _) => number
    _ => ""
  }
  @github_client.get_pull(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      number,
    },
    generation,
    result => emit(Load(PullCommitMetadataLoaded(generation, result))),
  )
}

///|
fn pull_metadata_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  @github_client.get_pull(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      number,
    },
    generation,
    result => emit(Load(PullMetadataLoaded(generation, attempt, result))),
  )
}

///|
fn pull_compare_request(
  reference : CommitRef,
  base_sha : String,
  head_sha : String,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @github_client.get_compare(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      base: base_sha,
      head: head_sha,
    },
    generation,
    result => emit(Load(PullCompareLoaded(generation, attempt, result))),
  )
}

///|
fn pull_files_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  page : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  @github_client.get_pull_files(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      number,
      page,
    },
    generation,
    result => emit(Load(PullFilesPageLoaded(generation, attempt, page, result))),
  )
}

///|
fn pull_validation_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  @github_client.get_pull(
    {
      owner: reference_repository(reference).owner,
      repo: reference_repository(reference).repo,
      number,
    },
    generation,
    result => emit(Load(PullValidationLoaded(generation, attempt, result))),
  )
}
