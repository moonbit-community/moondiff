///|
pub(all) enum ChangeTarget {
  Commit(String)
  PullRequest(String)
  PullCommit(String, String)
} derive(Eq)

///|
pub(all) struct CommitRef {
  owner : String
  repo : String
  target : ChangeTarget
} derive(Eq)

///|
pub fn commit_reference(
  owner : String,
  repo : String,
  sha : String,
) -> CommitRef {
  { owner, repo, target: Commit(sha), }
}

///|
pub fn pull_reference(
  owner : String,
  repo : String,
  number : String,
) -> CommitRef {
  { owner, repo, target: PullRequest(number), }
}

///|
pub fn pull_commit_reference(
  owner : String,
  repo : String,
  number : String,
  sha : String,
) -> CommitRef {
  { owner, repo, target: PullCommit(number, sha), }
}

///|
fn ascii_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
pub fn valid_owner(owner : String) -> Bool {
  if owner.length() == 0 || owner.length() > 39 {
    return false
  }
  if owner.get_char(0) == Some('-') ||
    owner.get_char(owner.length() - 1) == Some('-') {
    return false
  }
  for c in owner {
    if !ascii_alphanumeric(c) && c != '-' {
      return false
    }
  }
  true
}

///|
pub fn valid_repo(repo : String) -> Bool {
  if repo.length() == 0 || repo.length() > 100 || repo == "." || repo == ".." {
    return false
  }
  for c in repo {
    if !ascii_alphanumeric(c) && c != '-' && c != '_' && c != '.' {
      return false
    }
  }
  true
}

///|
pub fn valid_sha(sha : String) -> Bool {
  if sha.length() < 7 || sha.length() > 64 {
    return false
  }
  for c in sha {
    if !c.is_ascii_hexdigit() {
      return false
    }
  }
  true
}

///|
pub fn valid_pull_number(number : String) -> Bool {
  if number.length() == 0 || number == "0" {
    return false
  }
  for c in number {
    if !c.is_ascii_digit() {
      return false
    }
  }
  true
}

///|
pub fn parse_change_url(input : String) -> Result[CommitRef, String] {
  let parsed = try @url.parse(input.trim().to_owned()) catch {
    _ => return Err("Enter a valid GitHub commit or pull request URL.")
  } noraise {
    parsed => parsed
  }
  if parsed.protocol != Https ||
    parsed.host.to_lower() != "github.com" ||
    parsed.port is Some(_) {
    return Err("Only HTTPS links on github.com are supported.")
  }
  let parts = parsed.path.split("/").map(StringView::to_owned).collect()
  let reference = match parts {
    [owner, repo, "commit", sha] => {
      if !valid_sha(sha) {
        return Err(
          "The commit SHA must contain 7 to 64 hexadecimal characters.",
        )
      }
      commit_reference(owner, repo, sha)
    }
    [owner, repo, "pull", number]
    | [owner, repo, "pull", number, "files"]
    | [owner, repo, "pull", number, "commits"] => {
      if !valid_pull_number(number) {
        return Err("The pull request number is invalid.")
      }
      pull_reference(owner, repo, number)
    }
    [owner, repo, "pull", number, "changes", sha]
    | [owner, repo, "pull", number, "commits", sha] => {
      if !valid_pull_number(number) {
        return Err("The pull request number is invalid.")
      }
      if !valid_sha(sha) {
        return Err(
          "The commit SHA must contain 7 to 64 hexadecimal characters.",
        )
      }
      pull_commit_reference(owner, repo, number, sha)
    }
    _ =>
      return Err(
        "Use a GitHub /commit/{sha}, /pull/{number}, or /pull/{number}/commits/{sha} URL.",
      )
  }
  if !valid_owner(reference.owner) || !valid_repo(reference.repo) {
    return Err("The repository owner or name is invalid.")
  }
  Ok(reference)
}

///|
#warnings("-unused_value")
pub fn commit_api_url(reference : CommitRef, page : Int) -> String {
  let sha = match reference.target {
    Commit(sha) | PullCommit(_, sha) => sha
    PullRequest(_) => return ""
  }
  "https://api.github.com/repos/\{reference.owner}/\{reference.repo}/commits/\{sha}?per_page=100&page=\{page}"
}

///|
pub fn pull_api_url(reference : CommitRef) -> String {
  let number = match reference.target {
    PullRequest(number) | PullCommit(number, _) => number
    Commit(_) => return ""
  }
  "https://api.github.com/repos/\{reference.owner}/\{reference.repo}/pulls/\{number}"
}

///|
#warnings("-unused_value")
pub fn compare_api_url(
  reference : CommitRef,
  base_sha : String,
  head_sha : String,
) -> String {
  guard reference.target is PullRequest(_) else { return "" }
  "https://api.github.com/repos/\{reference.owner}/\{reference.repo}/compare/\{base_sha}...\{head_sha}"
}

///|
#warnings("-unused_value")
pub fn pull_files_api_url(reference : CommitRef, page : Int) -> String {
  "\{pull_api_url(reference)}/files?per_page=100&page=\{page}"
}
