///|
pub(all) enum ChangeTarget {
  Commit(String)
  PullRequest(String)
  PullCommit(String, String)
  Range(String, String)
  PullRange(String, String, String)
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
pub fn range_reference(
  owner : String,
  repo : String,
  base : String,
  head : String,
) -> CommitRef {
  { owner, repo, target: Range(base, head), }
}

///|
pub fn pull_range_reference(
  owner : String,
  repo : String,
  number : String,
  base : String,
  head : String,
) -> CommitRef {
  { owner, repo, target: PullRange(number, base, head), }
}

///|
pub fn range_endpoints(value : String) -> (String, String)? {
  guard value.split_once("..") is Some((base, head)) else { return None }
  let base = base.to_owned()
  let head = head.to_owned()
  if valid_sha(base) && valid_sha(head) {
    Some((base, head))
  } else {
    None
  }
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
  if number.length() == 0 || number.get_char(0) == Some('0') {
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
    [owner, repo, "compare", interval] => {
      guard range_endpoints(interval) is Some((base, head)) else {
        return Err("Use two commit SHAs separated by .. in a compare link.")
      }
      range_reference(owner, repo, base, head)
    }
    _ => return Err("Use a GitHub commit, pull request, or compare/A..B URL.")
  }
  if !valid_owner(reference.owner) || !valid_repo(reference.repo) {
    return Err("The repository owner or name is invalid.")
  }
  Ok(reference)
}
