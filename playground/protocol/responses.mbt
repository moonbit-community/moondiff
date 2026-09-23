///|
pub(all) struct ApiError {
  status : Int
  code : String
  message : String
} derive(Eq, FromJson, ToJson)

///|
pub(all) enum Response[T] {
  Success(value~ : T)
  Failure(error~ : ApiError)
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) enum RpcValue {
  ViewerPulls(ApiViewerPulls)
  PullCommits(ApiPullCommits)
  Commit(ApiCommit)
  Pull(ApiPull)
  PullMergeStatus(ApiPullMergeStatus)
  PullMergeResult(ApiPullMergeResult)
  PullViewed(ApiPullViewed)
  FileViewed(ApiFileViewedResult)
  Compare(ApiCompare)
  RangeCompare(ApiRangeCompare)
  PullCommitPage(Array[ApiRangeCommit])
  ResolvedSha(String)
  Files(Array[ApiFile])
  Content(ApiSource)
  Comments(ApiCommentBundle)
  IssueComment(ApiIssueComment)
  ReviewComment(ApiReviewComment)
  CommitComment(ApiCommitComment)
  Deleted(DeleteResult)
} derive(Eq, FromJson(style="legacy"), ToJson(style="legacy"))

///|
pub(all) struct ApiSource {
  base64 : String
  size : Int
  content_type : String
} derive(Eq, FromJson, ToJson)

///|
pub fn ApiSource::decode(self : ApiSource) -> Bytes raise {
  let bytes = @base64.decode(self.base64)
  guard self.size >= 0 && bytes.length() == self.size else {
    raise ProtocolError("invalid_server_response", "Invalid source size.")
  }
  bytes
}
