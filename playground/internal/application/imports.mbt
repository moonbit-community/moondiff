///|
using @github {
  type ApiCommit,
  type ApiCompare,
  type ApiFile,
  type ApiPull,
  type CommitRef,
  type RepositoryRef,
  type SourceLocation,
  branch_repository,
  check_source,
  merge_file_pages,
  parse_change_url,
  reference_repository,
  same_pull_snapshot,
  should_fetch_next_page,
  should_fetch_next_pull_page,
  source_pair_for_revisions,
  validate_pull_files,
}

///|
using @review {type ReviewAnchor}

///|
using @change {
  type ChangeView,
  type DiffAlgorithm,
  type DiffCache,
  type SideLoad,
  type SourceSide,
  type ViewMode,
  ensure_file_document,
  ensure_expanded_file_documents,
  finish_commit,
  finish_pull,
  initial_side,
  set_file_state,
  source_requests_for_file,
}

///|
using @github_client {extension_host_enabled, gateway_json_request}

///|
using @comments {
  type ApiCommentBundle,
  type ApiCommitComment,
  type ApiIssueComment,
  type ApiReviewComment,
  type Session,
}

///|
using @routing {
  browser_current_url,
  canonical_github_url,
  playground_share_url,
  reference_from_playground_url,
  reference_from_route,
}

///|
using @comment_requests {
  comment_failure,
  type ApiAuthStatus,
  error_message,
  comment_failure_message,
}
