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
priv struct ApiPullBranch {
  sha : String
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
  let encoded = StringBuilder::new(size_hint=bytes.length())
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
fn raw_url(reference : CommitRef, revision : String, path : String) -> String {
  "https://raw.githubusercontent.com/\{reference.owner}/\{reference.repo}/\{revision}/\{percent_encode_path(path)}"
}

///|
priv struct SourcePair {
  old_url : String?
  new_url : String?
}

///|
fn source_pair(
  reference : CommitRef,
  commit_sha : String,
  parent_sha : String?,
  file : ApiFile,
) -> SourcePair {
  let old_path = file.previous_filename.unwrap_or(file.filename)
  let old_url = if file.status == "added" || parent_sha is None {
    None
  } else {
    Some(raw_url(reference, parent_sha.unwrap(), old_path))
  }
  let new_url = if file.status == "removed" {
    None
  } else {
    Some(raw_url(reference, commit_sha, file.filename))
  }
  { old_url, new_url }
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
  let mut line_count = 1
  for c in text {
    if c == '\n' {
      line_count += 1
      if line_count > MAX_SOURCE_LINES {
        return Rejected("Cannot render: one side exceeds 20,000 lines.", false)
      }
    }
  }
  let normalized = text.replace_all(old="\r\n", new="\n")
  Renderable(normalized.split("\n").map(StringView::to_owned).collect())
}
