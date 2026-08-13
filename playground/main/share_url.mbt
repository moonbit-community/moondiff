// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

///|
fn canonical_github_url(reference : CommitRef) -> String {
  "https://github.com/\{reference.owner}/\{reference.repo}/commit/\{reference.sha}"
}

///|
fn playground_route(reference : CommitRef) -> String {
  "#/\{reference.owner}/\{reference.repo}/commit/\{reference.sha}"
}

///|
fn reference_from_route(fragment : String?) -> Result[CommitRef?, String] {
  guard fragment is Some(value) && !value.is_empty() else { return Ok(None) }
  let parts : Array[String] = value
    .split("/")
    .map(StringView::to_owned)
    .collect()
  let reference = match parts {
    ["", owner, repo, "commit", sha] | [owner, repo, "commit", sha] =>
      CommitRef::{ owner, repo, sha }
    _ => return Err("This shared playground link is not valid.")
  }
  if !valid_owner(reference.owner) ||
    !valid_repo(reference.repo) ||
    !valid_sha(reference.sha) {
    return Err("This shared playground link is not valid.")
  }
  Ok(Some(reference))
}

///|
fn reference_from_playground_url(input : String) -> Result[CommitRef?, String] {
  let parsed = try @url.parse(input) catch {
    _ => return Err("This shared playground link is not valid.")
  } noraise {
    parsed => parsed
  }
  reference_from_route(parsed.fragment)
}

///|
extern "js" fn browser_current_url() -> String = "() => window.location.href"

///|
extern "js" fn browser_base_url() -> String = "() => window.location.origin + window.location.pathname"

///|
fn playground_share_url(reference : CommitRef) -> String {
  "\{browser_base_url()}\{playground_route(reference)}"
}
