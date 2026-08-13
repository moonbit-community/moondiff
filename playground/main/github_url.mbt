// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

///|
priv struct CommitRef {
  owner : String
  repo : String
  sha : String
} derive(Eq)

///|
fn ascii_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
fn valid_owner(owner : String) -> Bool {
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
fn valid_repo(repo : String) -> Bool {
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
fn valid_sha(sha : String) -> Bool {
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
fn valid_pull_number(number : String) -> Bool {
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
fn parse_commit_url(input : String) -> Result[CommitRef, String] {
  let parsed = try @url.parse(input.trim().to_owned()) catch {
    _ => return Err("Enter a valid GitHub commit URL.")
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
    [owner, repo, "commit", sha] => { owner, repo, sha }
    [owner, repo, "pull", number, "changes", sha] => {
      if !valid_pull_number(number) {
        return Err("The pull request number is invalid.")
      }
      { owner, repo, sha }
    }
    _ =>
      return Err("Use a GitHub commit URL or /pull/{number}/changes/{sha} URL.")
  }
  if !valid_owner(reference.owner) || !valid_repo(reference.repo) {
    return Err("The repository owner or name is invalid.")
  }
  if !valid_sha(reference.sha) {
    return Err("The commit SHA must contain 7 to 64 hexadecimal characters.")
  }
  Ok(reference)
}

///|
fn commit_api_url(reference : CommitRef, page : Int) -> String {
  "https://api.github.com/repos/\{reference.owner}/\{reference.repo}/commits/\{reference.sha}?per_page=100&page=\{page}"
}
