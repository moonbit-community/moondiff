// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

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
#warnings("-unused_value")
fn decode_commit(body : String) -> ApiCommit raise {
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
fn first_parent(commit : ApiCommit) -> String? {
  commit.parents.get(0).map(parent => parent.sha)
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
