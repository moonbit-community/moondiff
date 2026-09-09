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
  gateway_json_request(
    "github.commit.get",
    repository,
    sha,
    "",
    page,
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
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
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
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
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
  gateway_json_request(
    "github.compare.get",
    reference_repository(reference),
    base_sha,
    head_sha,
    0,
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
  gateway_json_request(
    "github.pull.files",
    reference_repository(reference),
    number,
    "",
    page,
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
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    result => emit(Load(PullValidationLoaded(generation, attempt, result))),
  )
}
