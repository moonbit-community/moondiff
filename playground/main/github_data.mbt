///|
priv struct ApiStats {
  additions : Int
  deletions : Int
  total : Int
} derive(Eq, FromJson)

///|
priv struct ApiCommitInfo {
  message : String
} derive(Eq, FromJson)

///|
priv struct ApiParent {
  sha : String
} derive(Eq, FromJson)

///|
priv struct ApiFile {
  filename : String
  previous_filename : String?
  status : String
  additions : Int
  deletions : Int
  changes : Int
  patch : String?
} derive(Eq, FromJson)

///|
priv struct ApiCommit {
  sha : String
  html_url : String
  commit : ApiCommitInfo
  parents : Array[ApiParent]
  stats : ApiStats
  files : Array[ApiFile]
} derive(Eq, FromJson)

///|
priv struct ApiRepository {
  full_name : String
} derive(Eq, FromJson)

///|
priv struct ApiPullBranch {
  sha : String
  repo : ApiRepository?
} derive(Eq, FromJson)

///|
priv struct ApiPull {
  title : String
  html_url : String
  base : ApiPullBranch
  head : ApiPullBranch
  additions : Int
  deletions : Int
  changed_files : Int
} derive(Eq, FromJson)

///|
priv struct ApiCompare {
  merge_base_commit : ApiParent
} derive(Eq, FromJson)

///|
#warnings("-unused_value")
fn decode_commit(body : String) -> ApiCommit raise {
  @json.from_json(@json.parse(body))
}

///|
#warnings("-unused_value")
fn decode_pull(body : String) -> ApiPull raise {
  @json.from_json(@json.parse(body))
}

///|
#warnings("-unused_value")
fn decode_compare(body : String) -> ApiCompare raise {
  @json.from_json(@json.parse(body))
}

///|
#warnings("-unused_value")
fn decode_pull_files(body : String) -> Array[ApiFile] raise {
  @json.from_json(@json.parse(body))
}

///|
priv enum FileDiffMode {
  MoonBitDiff
  LineDiff
} derive(Eq)

///|
fn file_diff_mode(file : ApiFile) -> FileDiffMode {
  if file.filename.has_suffix(".mbt") ||
    file.previous_filename.map(path => path.has_suffix(".mbt")).unwrap_or(false) {
    MoonBitDiff
  } else {
    LineDiff
  }
}

///|
fn merge_file_pages(
  accumulated : ArrayView[ApiFile],
  page : ArrayView[ApiFile],
) -> Array[ApiFile] {
  let merged : Array[ApiFile] = []
  for file in accumulated {
    merged.push(file)
  }
  for file in page {
    merged.push(file)
  }
  merged
}

///|
fn should_fetch_next_page(page : Int, file_count : Int) -> Bool {
  file_count == 100 && page < 30
}

///|
const MAX_PULL_FILES : Int = 3_000

///|
const PULL_FILE_LIMIT_ERROR : String = "This pull request changes more than GitHub's 3,000-file API limit, so its complete diff cannot be loaded."

///|
fn should_fetch_next_pull_page(
  page : Int,
  page_file_count : Int,
  accumulated_file_count : Int,
  expected_file_count : Int?,
) -> Bool {
  if expected_file_count is Some(expected) && accumulated_file_count >= expected {
    return false
  }
  page_file_count == 100 && page < 30
}

///|
fn validate_pull_files(
  pull : ApiPull,
  files : ArrayView[ApiFile],
) -> Result[Unit, String] {
  if pull.changed_files > MAX_PULL_FILES {
    return Err(PULL_FILE_LIMIT_ERROR)
  }
  if files.length() != pull.changed_files {
    return Err(
      "GitHub returned \{files.length()} files, but the pull request metadata reports \{pull.changed_files}; the complete diff cannot be shown.",
    )
  }
  Ok(())
}

///|
fn first_parent(commit : ApiCommit) -> String? {
  commit.parents.get(0).map(parent => parent.sha)
}

///|
fn pull_merge_base(compare : ApiCompare) -> String {
  compare.merge_base_commit.sha
}

///|
fn same_pull_snapshot(initial : ApiPull, verified : ApiPull) -> Bool {
  initial.base.sha == verified.base.sha &&
  initial.head.sha == verified.head.sha &&
  initial.base.repo == verified.base.repo &&
  initial.head.repo == verified.head.repo &&
  initial.changed_files == verified.changed_files
}

///|
fn pull_stats(pull : ApiPull) -> ApiStats {
  {
    additions: pull.additions,
    deletions: pull.deletions,
    total: pull.additions + pull.deletions,
  }
}

///|
fn percent_encode_path(path : String) -> String {
  let bytes = @utf8.encode(path)
  let hex = "0123456789ABCDEF"
  let encoded = StringBuilder(size_hint=bytes.length())
  for byte in bytes {
    let value = byte.to_int()
    if (value >= 'a' && value <= 'z') ||
      (value >= 'A' && value <= 'Z') ||
      (value >= '0' && value <= '9') ||
      value == '-' ||
      value == '_' ||
      value == '.' ||
      value == '~' ||
      value == '/' {
      encoded.write_char(byte.to_char())
    } else {
      encoded.write_char('%')
      encoded.write_view(
        hex.view(start_offset=value / 16, end_offset=value / 16 + 1),
      )
      encoded.write_view(
        hex.view(start_offset=value % 16, end_offset=value % 16 + 1),
      )
    }
  }
  encoded.to_string()
}

///|
priv struct RepositoryRef {
  owner : String
  repo : String
} derive(Eq)

///|
priv struct Revision {
  repository : RepositoryRef
  sha : String
} derive(Eq)

///|
fn reference_repository(reference : CommitRef) -> RepositoryRef {
  { owner: reference.owner, repo: reference.repo }
}

///|
fn repository_from_full_name(full_name : String) -> RepositoryRef? {
  match full_name.split("/").map(StringView::to_owned).collect() {
    [owner, repo] if valid_owner(owner) && valid_repo(repo) =>
      Some({ owner, repo })
    _ => None
  }
}

///|
fn branch_repository(
  branch : ApiPullBranch,
  fallback : RepositoryRef,
) -> RepositoryRef {
  if branch.repo is Some(repository) {
    repository_from_full_name(repository.full_name).unwrap_or(fallback)
  } else {
    fallback
  }
}

///|
fn commit_revisions(
  reference : CommitRef,
  sha : String,
  parent_sha : String?,
) -> (Revision?, Revision) {
  let repository = reference_repository(reference)
  (parent_sha.map(parent => { repository, sha: parent }), { repository, sha })
}

///|
fn repository_commit_revisions(
  repository : RepositoryRef,
  sha : String,
  parent_sha : String?,
) -> (Revision?, Revision) {
  (parent_sha.map(parent => { repository, sha: parent }), { repository, sha })
}

///|
fn pull_revisions(
  reference : CommitRef,
  pull : ApiPull,
  compare : ApiCompare,
) -> (Revision?, Revision) {
  let fallback = reference_repository(reference)
  (
    Some({
      repository: branch_repository(pull.base, fallback),
      sha: pull_merge_base(compare),
    }),
    { repository: branch_repository(pull.head, fallback), sha: pull.head.sha },
  )
}

///|
fn raw_url_for_repository(
  repository : RepositoryRef,
  revision : String,
  path : String,
) -> String {
  "https://raw.githubusercontent.com/\{repository.owner}/\{repository.repo}/\{revision}/\{percent_encode_path(path)}"
}

///|
#warnings("-unused_value")
fn raw_url(reference : CommitRef, revision : String, path : String) -> String {
  raw_url_for_repository(reference_repository(reference), revision, path)
}

///|
priv struct SourceLocation {
  repository : RepositoryRef
  revision : String
  path : String
}

///|
priv struct SourcePair {
  old_url : String?
  new_url : String?
  old_location : SourceLocation?
  new_location : SourceLocation?
}

///|
fn source_pair_for_revisions(
  old_revision : Revision?,
  new_revision : Revision,
  file : ApiFile,
) -> SourcePair {
  let old_path = file.previous_filename.unwrap_or(file.filename)
  let old_location = if file.status == "added" || old_revision is None {
    None
  } else {
    let revision = old_revision.unwrap()
    Some({
      repository: revision.repository,
      revision: revision.sha,
      path: old_path,
    })
  }
  let new_location = if file.status == "removed" {
    None
  } else {
    Some({
      repository: new_revision.repository,
      revision: new_revision.sha,
      path: file.filename,
    })
  }
  {
    old_url: old_location.map(location => {
      raw_url_for_repository(
        location.repository,
        location.revision,
        location.path,
      )
    }),
    new_url: new_location.map(location => {
      raw_url_for_repository(
        location.repository,
        location.revision,
        location.path,
      )
    }),
    old_location,
    new_location,
  }
}

///|
#warnings("-unused_value")
fn source_pair(
  reference : CommitRef,
  commit_sha : String,
  parent_sha : String?,
  file : ApiFile,
) -> SourcePair {
  let (old_revision, new_revision) = commit_revisions(
    reference, commit_sha, parent_sha,
  )
  source_pair_for_revisions(old_revision, new_revision, file)
}

///|
priv enum CheckedSource {
  Renderable(Array[String])
  Rejected(String, Bool)
}

///|
const MAX_SOURCE_BYTES : Int = 1_048_576

///|
const MAX_SOURCE_LINES : Int = 20_000

///|
fn check_source(bytes : Bytes) -> CheckedSource {
  if bytes.length() > MAX_SOURCE_BYTES {
    return Rejected("Cannot render: one side is larger than 1 MiB.", false)
  }
  let text = try @utf8.decode(bytes) catch {
    _ =>
      return Rejected(
        "Cannot render: the file is binary or is not valid UTF-8.", true,
      )
  } noraise {
    text => text
  }
  if text.contains("\u{0000}") {
    return Rejected("Cannot render: the file contains a NUL byte.", true)
  }
  if @source_text.split_lines_bounded(text, max_lines=MAX_SOURCE_LINES)
    is Some(lines) {
    Renderable(lines)
  } else {
    Rejected("Cannot render: one side exceeds 20,000 lines.", false)
  }
}
