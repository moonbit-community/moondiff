///|
using @github {type ApiPull, type CommitRef, reference_repository}

///|
using @review {type ReviewAnchor}

///|
using @comments {
  type ApiCommentBundle,
  type ApiIssueComment,
  type ApiReviewComment,
  type ApiCommitComment,
  type DeleteResult,
  type CommentId,
}

///|
using @github_client {
  extension_error_code,
  extension_host_enabled,
  extension_rpc_json,
  extension_rpc_request,
  gateway_json_request,
}
