///|
pub(all) enum CommentSide {
  Left
  Right
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) enum CommentTarget {
  Commit(sha~ : String)
  Pull(number~ : String)
  PullCommit(number~ : String, sha~ : String)
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct CommitGet {
  owner : String
  repo : String
  sha : String
  page : Int
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullGet {
  owner : String
  repo : String
  number : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct CompareGet {
  owner : String
  repo : String
  base : String
  head : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct PullFiles {
  owner : String
  repo : String
  number : String
  page : Int
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ContentGet {
  owner : String
  repo : String
  path : String
  revision : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct CommentsList {
  owner : String
  repo : String
  target : CommentTarget
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct IssueCommentCreate {
  owner : String
  repo : String
  number : String
  body : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ReviewCommentCreate {
  owner : String
  repo : String
  number : String
  commit_id : String
  path : String
  line : Int
  side : CommentSide
  body : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct CommitCommentCreate {
  owner : String
  repo : String
  sha : String
  path : String
  position : Int
  body : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ReviewReplyCreate {
  owner : String
  repo : String
  number : String
  comment_id : Int64
  body : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct CommentDelete {
  owner : String
  repo : String
  comment_id : Int64
} derive(Eq, FromJson, ToJson)

///|
pub(all) enum GitHubRequest {
  CommitGet(CommitGet)
  PullGet(PullGet)
  CompareGet(CompareGet)
  PullFiles(PullFiles)
  ContentGet(ContentGet)
  CommentsList(CommentsList)
  IssueCommentCreate(IssueCommentCreate)
  ReviewCommentCreate(ReviewCommentCreate)
  CommitCommentCreate(CommitCommentCreate)
  ReviewReplyCreate(ReviewReplyCreate)
  IssueCommentDelete(CommentDelete)
  ReviewCommentDelete(CommentDelete)
  CommitCommentDelete(CommentDelete)
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct RpcRequest {
  v : Int
  request : GitHubRequest
} derive(Eq, FromJson, ToJson)
