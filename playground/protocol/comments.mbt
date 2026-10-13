///|
pub(all) struct ApiCommentUser {
  login : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiIssueComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiReviewComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String
  line : Int32?
  original_line : Int32?
  side : CommentSide?
  position : Int32?
  commit_id : String
  in_reply_to_id : Int64?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCommitComment {
  id : Int64
  body : String
  html_url : String
  created_at : String
  user : ApiCommentUser?
  path : String?
  position : Int32?
  line : Int32?
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ApiCommentBundle {
  issue_comments : Array[ApiIssueComment]
  review_comments : Array[ApiReviewComment]
  commit_comments : Array[ApiCommitComment]
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct DeleteResult {
  deleted : Bool
} derive(Eq, FromJson, ToJson)
