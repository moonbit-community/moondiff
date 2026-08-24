///|
priv enum ViewMode {
  Split
  Unified
} derive(Eq)

///|
priv enum DiffAlgorithm {
  LexicalAlgorithm
  AstAlgorithm
} derive(Eq)

///|
priv enum SourceSide {
  Old
  New
}

///|
priv enum SideLoad {
  NotRequested
  Loading
  Ready(Array[String])
  CannotRender(String, Bool)
  LoadFailed(String)
} derive(Eq)

///|
priv struct CachedDiffResult {
  document : @mbtdiff.DiffDocument
  status : @mbtdiff.DiffStatus
  fallbacks : ArrayView[@mbtdiff.FallbackInfo]
} derive(Eq)

///|
priv struct DiffCache {
  line : CachedDiffResult?
  lexical : CachedDiffResult?
  lexical_ignoring_comments : CachedDiffResult?
  lexical_ignoring_tests : CachedDiffResult?
  lexical_ignoring_comments_and_tests : CachedDiffResult?
  ast : CachedDiffResult?
  ast_ignoring_comments : CachedDiffResult?
  ast_ignoring_tests : CachedDiffResult?
  ast_ignoring_comments_and_tests : CachedDiffResult?
} derive(Eq)

///|
fn empty_diff_cache() -> DiffCache {
  {
    line: None,
    lexical: None,
    lexical_ignoring_comments: None,
    lexical_ignoring_tests: None,
    lexical_ignoring_comments_and_tests: None,
    ast: None,
    ast_ignoring_comments: None,
    ast_ignoring_tests: None,
    ast_ignoring_comments_and_tests: None,
  }
}

///|
priv struct FileState {
  file : ApiFile
  diff_mode : FileDiffMode
  expanded : Bool
  old_side : SideLoad
  new_side : SideLoad
  diff_cache : DiffCache
} derive(Eq)

///|
priv struct ChangeView {
  reference : CommitRef
  sha : String
  parent_sha : String?
  old_revision : Revision?
  new_revision : Revision
  message : String
  html_url : String
  stats : ApiStats
  total_files : Int
  files : Array[FileState]
} derive(Eq)

///|
priv enum Phase {
  Idle
  LoadingCommit(
    reference~ : CommitRef,
    repository~ : RepositoryRef,
    page~ : Int,
    first~ : ApiCommit?,
    files~ : Array[ApiFile]
  )
  LoadingPullMetadata(reference~ : CommitRef, attempt~ : Int)
  LoadingPullCommitMetadata(reference~ : CommitRef)
  LoadingPullSnapshot(
    reference~ : CommitRef,
    attempt~ : Int,
    metadata~ : ApiPull,
    compare~ : ApiCompare?,
    page~ : Int,
    files~ : Array[ApiFile]
  )
  ValidatingPullSnapshot(
    reference~ : CommitRef,
    attempt~ : Int,
    metadata~ : ApiPull,
    compare~ : ApiCompare,
    files~ : Array[ApiFile]
  )
  LoadFailed(String)
  Showing(ChangeView)
} derive(Eq)

///|
priv enum CopyStatus {
  CopyReady
  Copied
  CopyError(String)
} derive(Eq)

///|
priv struct Model {
  input : String
  generation : Int
  view_mode : ViewMode
  diff_algorithm : DiffAlgorithm
  ignore_comments : Bool
  ignore_tests : Bool
  phase : Phase
  route : CommitRef?
  share_url : String?
  copy_status : CopyStatus
  backend_status : BackendStatus
  analysis_status : AnalysisStatus
  review : ReviewState
} derive(Eq)

///|
fn initial_model() -> Model {
  {
    input: "",
    generation: 0,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    ignore_comments: false,
    ignore_tests: false,
    phase: Idle,
    route: None,
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendProbing,
    analysis_status: AnalysisIdle,
    review: initial_review_state(),
  }
}

///|
priv enum Msg {
  InputChanged(String)
  Submit
  RouteChanged(@url.Url)
  ToggleView
  SelectDiffAlgorithm(DiffAlgorithm)
  ToggleIgnoreComments
  ToggleIgnoreTests
  CopyShareLink
  ShareCopied
  ShareCopyFailed(String)
  CommitPageLoaded(Int, Int, Result[ApiCommit, Error])
  ToggleFile(Int, Int)
  RetryFile(Int, Int)
  SourceLoaded(Int, Int, SourceSide, Result[(String, Bytes), Error])
  HealthLoaded(Result[HealthResponse, Error])
  AnalyzeChanges
  AnalysisLoaded(Int, Result[AnalysisResponse, String])
  ToggleAnalysisGroup(Int)
  PullMetadataLoaded(Int, Int, Result[ApiPull, Error])
  PullCompareLoaded(Int, Int, Result[ApiCompare, Error])
  PullFilesPageLoaded(Int, Int, Int, Result[Array[ApiFile], Error])
  PullValidationLoaded(Int, Int, Result[ApiPull, Error])
  PullCommitMetadataLoaded(Int, Result[ApiPull, Error])
  AuthStatusLoaded(Result[ApiAuthStatus, Error])
  StartDeviceAuthorization
  DeviceAuthorizationStarted(Result[ApiAuthStatus, Error])
  PollDeviceAuthorization(String)
  DeviceAuthorizationPolled(String, Result[ApiAuthStatus, Error])
  CancelDeviceAuthorization(String)
  DeviceAuthorizationCancelled(String, Result[ApiAuthStatus, Error])
  CopyDeviceCode
  DeviceCodeCopied(String)
  DeviceCodeCopyFailed(String, String)
  Logout
  AuthLogoutFinished(Result[ApiAuthStatus, Error])
  RefreshComments
  CommentsLoaded(Int, Result[ApiCommentBundle, Error])
  VisibilityChanged(Bool)
  OpenOverallDraft
  OpenInlineDraft(Int, ReviewAnchor)
  OpenReplyDraft(Int64)
  DraftBodyChanged(String)
  CancelDraft
  SubmitDraft
  CommentHeadChecked(Int, ReviewAnchor, Result[ApiPull, Error])
  IssueCommentCreated(Int, Result[ApiIssueComment, Error])
  ReviewCommentCreated(Int, Result[ApiReviewComment, Error])
  CommitCommentCreated(Int, Result[ApiCommitComment, Error])
  ReviewReplyCreated(Int, Result[ApiReviewComment, Error])
}

///|
priv suberror ExtensionRequestError {
  ExtensionRequestError(status~ : Int, code~ : String, detail~ : String)
}

///|
impl Show for ExtensionRequestError with fn output(self, logger) {
  match self {
    ExtensionRequestError(status~, code~, detail~) =>
      logger.write_string(
        "Moondiff extension request failed (status \{status}, \{code}): \{detail}",
      )
  }
}

///|
fn extension_error_code(error : Error) -> String? {
  match error {
    ExtensionRequestError(status=_, code~, detail=_) => Some(code)
    _ => None
  }
}

///|
fn error_message(error : Error, api : Bool) -> String {
  let detail = error.to_string()
  let lower = detail.to_lower()
  if api {
    match extension_error_code(error) {
      Some("rate_limit") =>
        return "GitHub API rate limit exceeded. Sign in or try again after the reset time."
      Some("authentication_required") =>
        return "Your GitHub session expired. Sign in again."
      Some("not_found_or_not_installed") =>
        return "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
      Some("permission_denied") =>
        return "GitHub denied this request. Install the app for this repository and check its permissions."
      _ => ()
    }
  }
  if api && extension_host_enabled() && lower.contains("rate limit") {
    "GitHub API rate limit exceeded. Sign in or try again after the reset time."
  } else if api && detail.contains("HTTP 401") && extension_host_enabled() {
    "Your GitHub session expired. Sign in again."
  } else if api && detail.contains("HTTP 403") {
    if extension_host_enabled() {
      "GitHub denied this request. Install the app for this repository and check its permissions."
    } else {
      "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later."
    }
  } else if api && detail.contains("HTTP 404") {
    if extension_host_enabled() {
      "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
    } else {
      "GitHub could not find that public repository, commit, or pull request."
    }
  } else {
    detail
  }
}

///|
priv suberror GitHubRequestError {
  GitHubRequestError(String)
}

///|
impl Show for GitHubRequestError with fn output(self, logger) {
  match self {
    GitHubRequestError(detail) => logger.write_string(detail)
  }
}

///|
fn commit_request(
  reference : CommitRef,
  repository : RepositoryRef,
  generation : Int,
  page : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let sha = match reference.target {
    Commit(sha) | PullCommit(_, sha) => sha
    PullRequest(_) => ""
  }
  gateway_json_request(
    "github.commit.get",
    repository,
    sha,
    "",
    page,
    generation,
    result => emit(CommitPageLoaded(generation, page, result)),
  )
}

///|
fn pull_commit_metadata_request(
  reference : CommitRef,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullCommit(number, _) => number
    _ => ""
  }
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    result => emit(PullCommitMetadataLoaded(generation, result)),
  )
}

///|
fn pull_metadata_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    result => emit(PullMetadataLoaded(generation, attempt, result)),
  )
}

///|
fn pull_compare_request(
  reference : CommitRef,
  base_sha : String,
  head_sha : String,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  gateway_json_request(
    "github.compare.get",
    reference_repository(reference),
    base_sha,
    head_sha,
    0,
    generation,
    result => emit(PullCompareLoaded(generation, attempt, result)),
  )
}

///|
fn pull_files_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  page : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  gateway_json_request(
    "github.pull.files",
    reference_repository(reference),
    number,
    "",
    page,
    generation,
    result => emit(PullFilesPageLoaded(generation, attempt, page, result)),
  )
}

///|
fn pull_validation_request(
  reference : CommitRef,
  generation : Int,
  attempt : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let number = match reference.target {
    PullRequest(number) => number
    _ => ""
  }
  gateway_json_request(
    "github.pull.get",
    reference_repository(reference),
    number,
    "",
    0,
    generation,
    result => emit(PullValidationLoaded(generation, attempt, result)),
  )
}

///|
fn initial_side(url : String?, expanded : Bool) -> SideLoad {
  if url is Some(_) {
    if expanded {
      Loading
    } else {
      NotRequested
    }
  } else {
    Ready([])
  }
}

///|
fn commands_for_file(
  file : ApiFile,
  old_revision : Revision?,
  new_revision : Revision,
  generation : Int,
  index : Int,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Cmd] {
  let pair = source_pair_for_revisions(old_revision, new_revision, file)
  let commands : Array[@rabbita.Cmd] = []
  if pair.old_location is Some(location) {
    commands.push(
      gateway_source_request(location, generation, index, Old, emit),
    )
  }
  if pair.new_location is Some(location) {
    commands.push(
      gateway_source_request(location, generation, index, New, emit),
    )
  }
  commands
}

///|
fn finish_change(
  reference : CommitRef,
  old_revision : Revision?,
  new_revision : Revision,
  message : String,
  html_url : String,
  stats : ApiStats,
  all_files : Array[ApiFile],
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> (ChangeView, @rabbita.Cmd) {
  let states : Array[FileState] = []
  let commands : Array[@rabbita.Cmd] = []
  let mut moonbit_file_count = 0
  for index, file in all_files {
    let diff_mode = file_diff_mode(file)
    let expanded = diff_mode is MoonBitDiff && moonbit_file_count < 20
    if diff_mode is MoonBitDiff {
      moonbit_file_count += 1
    }
    let pair = source_pair_for_revisions(old_revision, new_revision, file)
    states.push({
      file,
      diff_mode,
      expanded,
      old_side: initial_side(pair.old_url, expanded),
      new_side: initial_side(pair.new_url, expanded),
      diff_cache: empty_diff_cache(),
    })
    if expanded {
      for
        command in commands_for_file(
          file, old_revision, new_revision, generation, index, emit,
        ) {
        commands.push(command)
      }
    }
  }
  (
    {
      reference,
      sha: new_revision.sha,
      parent_sha: old_revision.map(revision => revision.sha),
      old_revision,
      new_revision,
      message,
      html_url,
      stats,
      total_files: all_files.length(),
      files: states,
    },
    @rabbita.batch(commands),
  )
}

///|
fn finish_commit(
  reference : CommitRef,
  repository : RepositoryRef,
  first : ApiCommit,
  all_files : Array[ApiFile],
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> (ChangeView, @rabbita.Cmd) {
  let (old_revision, new_revision) = repository_commit_revisions(
    repository,
    first.sha,
    first_parent(first),
  )
  finish_change(
    reference,
    old_revision,
    new_revision,
    first.commit.message,
    first.html_url,
    first.stats,
    all_files,
    generation,
    emit,
  )
}

///|
fn finish_pull(
  reference : CommitRef,
  pull : ApiPull,
  compare : ApiCompare,
  all_files : Array[ApiFile],
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> Result[(ChangeView, @rabbita.Cmd), String] {
  match validate_pull_files(pull, all_files) {
    Err(message) => Err(message)
    Ok(_) => {
      let (old_revision, new_revision) = pull_revisions(
        reference, pull, compare,
      )
      Ok(
        finish_change(
          reference,
          old_revision,
          new_revision,
          pull.title,
          pull.html_url,
          pull_stats(pull),
          all_files,
          generation,
          emit,
        ),
      )
    }
  }
}

///|
fn set_file_state(
  view : ChangeView,
  index : Int,
  state : FileState,
) -> ChangeView {
  let files = view.files.copy()
  files[index] = state
  {
    reference: view.reference,
    sha: view.sha,
    parent_sha: view.parent_sha,
    old_revision: view.old_revision,
    new_revision: view.new_revision,
    message: view.message,
    html_url: view.html_url,
    stats: view.stats,
    total_files: view.total_files,
    files,
  }
}

///|
fn with_phase(model : Model, phase : Phase) -> Model {
  {
    input: model.input,
    generation: model.generation,
    view_mode: model.view_mode,
    diff_algorithm: model.diff_algorithm,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
    phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status: model.backend_status,
    analysis_status: model.analysis_status,
    review: model.review,
  }
}

///|
fn with_backend_status(model : Model, backend_status : BackendStatus) -> Model {
  {
    input: model.input,
    generation: model.generation,
    view_mode: model.view_mode,
    diff_algorithm: model.diff_algorithm,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
    phase: model.phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status,
    analysis_status: model.analysis_status,
    review: model.review,
  }
}

///|
fn with_analysis_status(
  model : Model,
  analysis_status : AnalysisStatus,
) -> Model {
  {
    input: model.input,
    generation: model.generation,
    view_mode: model.view_mode,
    diff_algorithm: model.diff_algorithm,
    ignore_comments: model.ignore_comments,
    ignore_tests: model.ignore_tests,
    phase: model.phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status: model.backend_status,
    analysis_status,
    review: model.review,
  }
}

///|
fn with_review(model : Model, review : ReviewState) -> Model {
  { ..model, review, }
}

///|
fn update_draft(
  model : Model,
  body? : String,
  submitting? : Bool,
  error? : String?,
) -> Model {
  guard model.review.draft is Some(draft) else { return model }
  with_review(
    model,
    review_state_with_draft(
      model.review,
      Some({
        kind: draft.kind,
        body: body.unwrap_or(draft.body),
        submitting: submitting.unwrap_or(draft.submitting),
        error: if error is Some(value) {
          value
        } else {
          draft.error
        },
      }),
    ),
  )
}

///|
fn comment_failure_message(error : Error) -> String {
  match extension_error_code(error) {
    Some("authentication_required") =>
      return "Your GitHub session expired. Sign in again, then retry."
    Some("not_found_or_not_installed") =>
      return "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
    Some("permission_denied") =>
      return "GitHub denied this action. Install the app for this repository and check its Pull requests permission."
    Some("invalid_comment_anchor") =>
      return "GitHub rejected this comment anchor. Refresh the diff and choose the line again."
    _ => ()
  }
  let detail = error_message(error, true)
  if detail.contains("HTTP 401") {
    "Your GitHub session expired. Sign in again, then retry."
  } else if detail.contains("HTTP 403") {
    "GitHub denied this action. Install the app for this repository and check its Pull requests permission."
  } else if detail.contains("HTTP 404") {
    "GitHub could not access this repository. Sign in and install the GitHub App for private repositories."
  } else if detail.contains("HTTP 422") {
    "GitHub rejected this comment anchor. Refresh the diff and choose the line again."
  } else {
    detail
  }
}

///|
fn model_with_comment_auth_failure(model : Model, error : Error) -> Model {
  match extension_error_code(error) {
    Some("authentication_required") =>
      with_review(
        model,
        review_state_with_auth(
          model.review,
          AuthFailed(comment_failure_message(error)),
        ),
      )
    _ => model
  }
}

///|
fn finish_comment_submission(
  model : Model,
  generation : Int,
  error : Error?,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if generation != model.generation {
    return (model, @rabbita.none)
  }
  if error is Some(error) {
    let failed = update_draft(
      model,
      submitting=false,
      error=Some(comment_failure_message(error)),
    )
    return (model_with_comment_auth_failure(failed, error), @rabbita.none)
  }
  guard model.route is Some(reference) else { return (model, @rabbita.none) }
  (
    with_review(model, {
      auth: model.review.auth,
      // Keep the object returned by GitHub visible while the authoritative
      // comment list refresh runs in the background.
      comments: model.review.comments,
      draft: None,
    }),
    @rabbita.batch([
      comments_request(reference, generation, emit),
      notify_github_page_command(),
    ]),
  )
}

///|
fn insert_issue_comment(model : Model, comment : ApiIssueComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.issue_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: comments,
        review_comments: bundle.review_comments,
        commit_comments: bundle.commit_comments,
      }),
    ),
  )
}

///|
fn insert_review_comment(model : Model, comment : ApiReviewComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.review_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: bundle.issue_comments,
        review_comments: comments,
        commit_comments: bundle.commit_comments,
      }),
    ),
  )
}

///|
fn insert_commit_comment(model : Model, comment : ApiCommitComment) -> Model {
  guard model.review.comments is CommentsReady(bundle) else { return model }
  let comments = bundle.commit_comments.copy()
  comments.push(comment)
  with_review(
    model,
    review_state_with_comments(
      model.review,
      CommentsReady({
        issue_comments: bundle.issue_comments,
        review_comments: bundle.review_comments,
        commit_comments: comments,
      }),
    ),
  )
}

///|
const PULL_CHANGED_ERROR : String = "This pull request changed while it was loading. Please try again."

///|
const MAX_PULL_LOAD_ATTEMPT : Int = 1

///|
fn show_pull(
  model : Model,
  reference : CommitRef,
  pull : ApiPull,
  compare : ApiCompare,
  files : Array[ApiFile],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match finish_pull(reference, pull, compare, files, model.generation, emit) {
    Err(message) => (with_phase(model, LoadFailed(message)), @rabbita.none)
    Ok((view, command)) =>
      (
        with_phase(
          model,
          Showing(
            ensure_expanded_file_documents(
              view,
              model.diff_algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests=model.ignore_tests,
            ),
          ),
        ),
        command,
      )
  }
}

///|
fn start_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if metadata.changed_files > MAX_PULL_FILES {
    return (with_phase(model, LoadFailed(PULL_FILE_LIMIT_ERROR)), @rabbita.none)
  }
  (
    with_phase(
      model,
      LoadingPullSnapshot(
        reference~,
        attempt~,
        metadata~,
        compare=None,
        page=1,
        files=[],
      ),
    ),
    @rabbita.batch([
      pull_compare_request(
        reference,
        metadata.base.sha,
        metadata.head.sha,
        model.generation,
        attempt,
        emit,
      ),
      pull_files_request(reference, model.generation, attempt, 1, emit),
    ]),
  )
}

///|
fn continue_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  compare : ApiCompare?,
  page : Int,
  files : Array[ApiFile],
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let loading = LoadingPullSnapshot(
    reference~,
    attempt~,
    metadata~,
    compare~,
    page~,
    files~,
  )
  guard compare is Some(loaded_compare) && page == 0 else {
    return (with_phase(model, loading), @rabbita.none)
  }
  (
    with_phase(
      model,
      ValidatingPullSnapshot(
        reference~,
        attempt~,
        metadata~,
        compare=loaded_compare,
        files~,
      ),
    ),
    pull_validation_request(reference, model.generation, attempt, emit),
  )
}

///|
fn validate_or_retry_pull_snapshot(
  model : Model,
  reference : CommitRef,
  attempt : Int,
  metadata : ApiPull,
  compare : ApiCompare,
  files : Array[ApiFile],
  verified : ApiPull,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  if !same_pull_snapshot(metadata, verified) {
    if attempt < MAX_PULL_LOAD_ATTEMPT {
      return start_pull_snapshot(model, reference, attempt + 1, verified, emit)
    }
    return (with_phase(model, LoadFailed(PULL_CHANGED_ERROR)), @rabbita.none)
  }
  match validate_pull_files(verified, files) {
    Err(message) =>
      if attempt < MAX_PULL_LOAD_ATTEMPT {
        start_pull_snapshot(model, reference, attempt + 1, verified, emit)
      } else {
        (with_phase(model, LoadFailed(message)), @rabbita.none)
      }
    Ok(_) => show_pull(model, reference, verified, compare, files, emit)
  }
}

///|
fn begin_change_load(
  model : Model,
  reference : CommitRef,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let generation = model.generation + 1
  let (phase, command) = match reference.target {
    Commit(_) => {
      let repository = reference_repository(reference)
      (
        LoadingCommit(reference~, repository~, page=1, first=None, files=[]),
        commit_request(reference, repository, generation, 1, emit),
      )
    }
    PullRequest(_) =>
      (
        LoadingPullMetadata(reference~, attempt=0),
        pull_metadata_request(reference, generation, 0, emit),
      )
    PullCommit(_, _) =>
      (
        LoadingPullCommitMetadata(reference~),
        pull_commit_metadata_request(reference, generation, emit),
      )
  }
  (
    {
      input: canonical_github_url(reference),
      generation,
      view_mode: model.view_mode,
      diff_algorithm: model.diff_algorithm,
      ignore_comments: model.ignore_comments,
      ignore_tests: model.ignore_tests,
      phase,
      route: Some(reference),
      share_url: Some(playground_share_url(reference)),
      copy_status: CopyReady,
      backend_status: model.backend_status,
      analysis_status: AnalysisIdle,
      review: if extension_host_enabled() {
        { auth: model.review.auth, comments: CommentsLoading, draft: None }
      } else {
        model.review
      },
    },
    if extension_host_enabled() {
      @rabbita.batch([command, comments_request(reference, generation, emit)])
    } else {
      command
    },
  )
}

///|
fn app_init(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  let model = initial_model()
  let (next, command) = match
    reference_from_playground_url(browser_current_url()) {
    Ok(Some(reference)) => begin_change_load(model, reference, emit)
    Ok(None) => (model, @rabbita.none)
    Err(message) => (with_phase(model, LoadFailed(message)), @rabbita.none)
  }
  if extension_host_enabled() {
    (next, @rabbita.batch([auth_status_request(emit), command]))
  } else {
    (next, @rabbita.batch([health_request(emit), command]))
  }
}

///|
fn app_subscriptions(_model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  if extension_host_enabled() {
    @sub.batch([
      @sub.on_url_changed(url => emit(RouteChanged(url))),
      @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
    ])
  } else {
    @sub.on_url_changed(url => emit(RouteChanged(url)))
  }
}

///|
fn side_from_result(result : Result[(String, Bytes), Error]) -> SideLoad {
  match result {
    Err(error) => LoadFailed(error_message(error, false))
    Ok((_, bytes)) =>
      match check_source(bytes) {
        Renderable(lines) => Ready(lines)
        Rejected(reason, skippable) => CannotRender(reason, skippable)
      }
  }
}

///|
fn prepare_all_sources(
  view : ChangeView,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> (ChangeView, Array[@rabbita.Cmd]) {
  let files = view.files.copy()
  let commands : Array[@rabbita.Cmd] = []
  for index, file in files {
    let pair = source_pair_for_revisions(
      view.old_revision,
      view.new_revision,
      file.file,
    )
    let old_side = match (file.old_side, pair.old_location) {
      (NotRequested | LoadFailed(_), Some(location)) => {
        commands.push(
          gateway_source_request(location, generation, index, Old, emit),
        )
        Loading
      }
      (side, _) => side
    }
    let new_side = match (file.new_side, pair.new_location) {
      (NotRequested | LoadFailed(_), Some(location)) => {
        commands.push(
          gateway_source_request(location, generation, index, New, emit),
        )
        Loading
      }
      (side, _) => side
    }
    files[index] = {
      file: file.file,
      diff_mode: file.diff_mode,
      expanded: file.expanded,
      old_side,
      new_side,
      diff_cache: file.diff_cache,
    }
  }
  (
    {
      reference: view.reference,
      sha: view.sha,
      parent_sha: view.parent_sha,
      old_revision: view.old_revision,
      new_revision: view.new_revision,
      message: view.message,
      html_url: view.html_url,
      stats: view.stats,
      total_files: view.total_files,
      files,
    },
    commands,
  )
}

///|
fn continue_analysis(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard model.analysis_status is PreparingSources &&
    model.phase is Showing(view) else {
    return (model, @rabbita.none)
  }
  for file in view.files {
    if blocking_source_problem(file) is Some(message) {
      return (
        with_analysis_status(
          model,
          AnalysisFailed("Could not prepare \{file.file.filename}: \{message}"),
        ),
        @rabbita.none,
      )
    }
  }
  if sources_pending(view) {
    return (model, @rabbita.none)
  }
  let ready_view = ensure_all_file_documents(
    view,
    model.diff_algorithm,
    ignore_comments=model.ignore_comments,
    ignore_tests=model.ignore_tests,
  )
  let ready_model = with_phase(model, Showing(ready_view))
  match
    build_analysis_request(
      ready_view,
      model.diff_algorithm,
      ignore_comments=model.ignore_comments,
      ignore_tests=model.ignore_tests,
    ) {
    Err(message) =>
      (
        with_analysis_status(ready_model, AnalysisFailed(message)),
        @rabbita.none,
      )
    Ok((payload, skipped)) =>
      if payload.hunks.is_empty() {
        (
          with_analysis_status(ready_model, AnalysisNoHunks(skipped)),
          @rabbita.none,
        )
      } else {
        (
          with_analysis_status(ready_model, Analyzing),
          analyze_request(payload, model.generation, emit),
        )
      }
  }
}

///|
fn apply_auth_status(
  model : Model,
  status : ApiAuthStatus,
  preserve_device_copy : Bool,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let auth = if preserve_device_copy {
    auth_status_from_api_preserving(status, model.review.auth)
  } else {
    auth_status_from_api(status)
  }
  let next = with_review(model, review_state_with_auth(model.review, auth))
  match auth {
    DeviceAuthorizing(device) =>
      (next, schedule_device_poll(device.flow_id, device.poll_after, emit))
    _ => (next, @rabbita.none)
  }
}

///|
fn finish_device_sign_in(
  model : Model,
  status : ApiAuthStatus,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let next = with_review(
    model,
    review_state_with_auth(model.review, auth_status_from_api(status)),
  )
  guard model.route is Some(reference) else { return (next, @rabbita.none) }
  if model.phase is LoadFailed(_) {
    return begin_change_load(next, reference, emit)
  }
  (
    with_review(next, review_state_with_comments(next.review, CommentsLoading)),
    comments_request(reference, model.generation, emit),
  )
}

///|
fn device_flow_is_current(model : Model, flow_id : String) -> Bool {
  match model.review.auth {
    DeviceAuthorizing(device) | DeviceCancelling(device) =>
      device.flow_id == flow_id
    _ => false
  }
}

///|
fn device_flow_is_cancelling(model : Model, flow_id : String) -> Bool {
  model.review.auth is DeviceCancelling(device) && device.flow_id == flow_id
}

///|
fn device_flow_is_authorizing(model : Model, flow_id : String) -> Bool {
  model.review.auth is DeviceAuthorizing(device) && device.flow_id == flow_id
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    AuthStatusLoaded(result) =>
      match result {
        Ok(status) => apply_auth_status(model, status, true, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    StartDeviceAuthorization =>
      if extension_host_enabled() {
        (
          with_review(model, review_state_with_auth(model.review, AuthChecking)),
          auth_device_start_request(emit),
        )
      } else {
        (model, @rabbita.none)
      }
    DeviceAuthorizationStarted(result) =>
      match result {
        Ok(status) if status.authenticated =>
          finish_device_sign_in(model, status, emit)
        Ok(status) => apply_auth_status(model, status, false, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    PollDeviceAuthorization(flow_id) =>
      if extension_host_enabled() && device_flow_is_authorizing(model, flow_id) {
        (model, auth_device_poll_request(flow_id, emit))
      } else {
        (model, @rabbita.none)
      }
    DeviceAuthorizationPolled(flow_id, result) => {
      if !device_flow_is_current(model, flow_id) {
        return (model, @rabbita.none)
      }
      if device_flow_is_cancelling(model, flow_id) {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) if status.authenticated =>
          finish_device_sign_in(model, status, emit)
        Ok(status) => {
          guard status.device_flow is Some(flow) && flow.flow_id == flow_id else {
            return (model, @rabbita.none)
          }
          apply_auth_status(model, status, true, emit)
        }
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    }
    CancelDeviceAuthorization(flow_id) => {
      guard extension_host_enabled() &&
        model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(model.review, DeviceCancelling(device)),
        ),
        auth_device_cancel_request(flow_id, emit),
      )
    }
    DeviceAuthorizationCancelled(flow_id, result) => {
      if !device_flow_is_cancelling(model, flow_id) {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => apply_auth_status(model, status, false, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    }
    CopyDeviceCode => {
      guard model.review.auth is DeviceAuthorizing(device) else {
        return (model, @rabbita.none)
      }
      (
        model,
        @clipboard.copy(
          Text(device.user_code),
          copied=emit(DeviceCodeCopied(device.flow_id)),
          failed=message => emit(DeviceCodeCopyFailed(device.flow_id, message)),
        ),
      )
    }
    DeviceCodeCopied(flow_id) => {
      guard model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(
            model.review,
            DeviceAuthorizing({ ..device, copy_status: DeviceCodeCopyDone }),
          ),
        ),
        @rabbita.none,
      )
    }
    DeviceCodeCopyFailed(flow_id, message) => {
      guard model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(
            model.review,
            DeviceAuthorizing({
              ..device,
              copy_status: DeviceCodeCopyError(message),
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    Logout =>
      if extension_host_enabled() {
        (
          with_review(model, review_state_with_auth(model.review, AuthChecking)),
          auth_logout_request(emit),
        )
      } else {
        (model, @rabbita.none)
      }
    AuthLogoutFinished(result) =>
      match result {
        Ok(status) =>
          (
            with_review(model, {
              auth: auth_status_from_api(status),
              comments: model.review.comments,
              draft: None,
            }),
            @rabbita.none,
          )
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    RefreshComments => {
      guard extension_host_enabled() && model.route is Some(reference) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_comments(model.review, CommentsLoading),
        ),
        comments_request(reference, model.generation, emit),
      )
    }
    VisibilityChanged(hidden) => {
      guard !hidden &&
        extension_host_enabled() &&
        model.route is Some(reference) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_comments(model.review, CommentsLoading),
        ),
        comments_request(reference, model.generation, emit),
      )
    }
    CommentsLoaded(generation, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      match result {
        Ok(bundle) =>
          (
            with_review(
              model,
              review_state_with_comments(model.review, CommentsReady(bundle)),
            ),
            @rabbita.none,
          )
        Err(error) => {
          let failed = with_review(
            model,
            review_state_with_comments(
              model.review,
              CommentsFailed(comment_failure_message(error)),
            ),
          )
          (model_with_comment_auth_failure(failed, error), @rabbita.none)
        }
      }
    }
    OpenOverallDraft => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: OverallDraft,
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    OpenInlineDraft(file_index, anchor) => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: InlineDraft(file_index, anchor),
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    OpenReplyDraft(comment_id) => {
      guard review_can_comment(model.review) else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({
              kind: ReplyDraft(comment_id),
              body: "",
              submitting: false,
              error: None,
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    DraftBodyChanged(body) => {
      guard model.review.draft is Some(draft) && !draft.submitting else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_draft(
            model.review,
            Some({ kind: draft.kind, body, submitting: false, error: None }),
          ),
        ),
        @rabbita.none,
      )
    }
    CancelDraft => {
      guard model.review.draft is Some(draft) && !draft.submitting else {
        return (model, @rabbita.none)
      }
      (
        with_review(model, review_state_with_draft(model.review, None)),
        @rabbita.none,
      )
    }
    SubmitDraft => {
      guard model.review.draft is Some(draft) &&
        !draft.submitting &&
        model.phase is Showing(view) else {
        return (model, @rabbita.none)
      }
      guard review_can_comment(model.review) else {
        return (
          update_draft(
            model,
            submitting=false,
            error=Some("Sign in with GitHub before posting a comment."),
          ),
          @rabbita.none,
        )
      }
      let body = draft.body.trim().to_owned()
      if body.is_empty() {
        return (
          update_draft(
            model,
            submitting=false,
            error=Some("Enter a comment before posting."),
          ),
          @rabbita.none,
        )
      }
      let submitting = with_review(
        model,
        review_state_with_draft(
          model.review,
          Some({ kind: draft.kind, body, submitting: true, error: None }),
        ),
      )
      let command = match (view.reference.target, draft.kind) {
        (PullRequest(number), OverallDraft) =>
          create_issue_comment_request(
            view.reference,
            number,
            body,
            model.generation,
            emit,
          )
        (PullRequest(number), InlineDraft(_, anchor)) =>
          comment_head_request(
            view.reference,
            number,
            anchor,
            model.generation,
            emit,
          )
        (Commit(sha), InlineDraft(_, anchor))
        | (PullCommit(_, sha), InlineDraft(_, anchor)) =>
          create_commit_comment_request(
            view.reference,
            sha,
            anchor,
            body,
            model.generation,
            emit,
          )
        (PullRequest(number), ReplyDraft(comment_id)) =>
          create_review_reply_request(
            view.reference,
            number,
            comment_id,
            body,
            model.generation,
            emit,
          )
        _ => @rabbita.none
      }
      (submitting, command)
    }
    CommentHeadChecked(generation, anchor, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.review.draft is Some(draft) &&
        draft.kind is InlineDraft(_, selected) &&
        selected == anchor &&
        model.phase is Showing(view) &&
        view.reference.target is PullRequest(number) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) => {
          let failed = update_draft(
            model,
            submitting=false,
            error=Some(comment_failure_message(error)),
          )
          (model_with_comment_auth_failure(failed, error), @rabbita.none)
        }
        Ok(pull) if pull.head.sha != view.sha => {
          let (refreshed, command) = begin_change_load(
            model,
            view.reference,
            emit,
          )
          (
            with_review(refreshed, {
              auth: model.review.auth,
              comments: CommentsLoading,
              draft: Some({
                kind: draft.kind,
                body: draft.body,
                submitting: false,
                error: Some(
                  "The pull request head changed. Moondiff refreshed the snapshot; review the new diff before retrying.",
                ),
              }),
            }),
            command,
          )
        }
        Ok(_) =>
          (
            model,
            create_review_comment_request(
              view.reference,
              number,
              view.sha,
              anchor,
              draft.body,
              generation,
              emit,
            ),
          )
      }
    }
    IssueCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_issue_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    ReviewCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_review_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    CommitCommentCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_commit_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    ReviewReplyCreated(generation, result) =>
      finish_comment_submission(
        match result {
          Ok(comment) => insert_review_comment(model, comment)
          Err(_) => model
        },
        generation,
        match result {
          Ok(_) => None
          Err(error) => Some(error)
        },
        emit,
      )
    InputChanged(value) =>
      (
        {
          input: value,
          generation: model.generation,
          view_mode: model.view_mode,
          diff_algorithm: model.diff_algorithm,
          ignore_comments: model.ignore_comments,
          ignore_tests: model.ignore_tests,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: CopyReady,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
          review: model.review,
        },
        @rabbita.none,
      )
    ToggleView =>
      (
        {
          input: model.input,
          generation: model.generation,
          view_mode: if model.view_mode is Split {
            Unified
          } else {
            Split
          },
          diff_algorithm: model.diff_algorithm,
          ignore_comments: model.ignore_comments,
          ignore_tests: model.ignore_tests,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: model.copy_status,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
          review: model.review,
        },
        @rabbita.none,
      )
    SelectDiffAlgorithm(algorithm) => {
      if algorithm == model.diff_algorithm {
        return (model, @rabbita.none)
      }
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests=model.ignore_tests,
            ),
          )
        other => other
      }
      (
        {
          input: model.input,
          generation: model.generation,
          view_mode: model.view_mode,
          diff_algorithm: algorithm,
          ignore_comments: model.ignore_comments,
          ignore_tests: model.ignore_tests,
          phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: model.copy_status,
          backend_status: model.backend_status,
          analysis_status: AnalysisIdle,
          review: model.review,
        },
        @rabbita.none,
      )
    }
    ToggleIgnoreComments => {
      let ignore_comments = !model.ignore_comments
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              model.diff_algorithm,
              ignore_comments~,
              ignore_tests=model.ignore_tests,
            ),
          )
        other => other
      }
      (
        { ..model, ignore_comments, phase, analysis_status: AnalysisIdle },
        @rabbita.none,
      )
    }
    ToggleIgnoreTests => {
      let ignore_tests = !model.ignore_tests
      let phase = match model.phase {
        Showing(view) =>
          Showing(
            ensure_expanded_file_documents(
              view,
              model.diff_algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests~,
            ),
          )
        other => other
      }
      (
        { ..model, ignore_tests, phase, analysis_status: AnalysisIdle },
        @rabbita.none,
      )
    }
    Submit =>
      match parse_change_url(model.input) {
        Err(message) =>
          (
            {
              input: model.input,
              generation: model.generation + 1,
              view_mode: model.view_mode,
              diff_algorithm: model.diff_algorithm,
              ignore_comments: model.ignore_comments,
              ignore_tests: model.ignore_tests,
              phase: LoadFailed(message),
              route: model.route,
              share_url: model.share_url,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
              review: model.review,
            },
            @rabbita.none,
          )
        Ok(reference) => {
          let already_at_route = model.route == Some(reference)
          let (next, request) = begin_change_load(model, reference, emit)
          let navigation = if already_at_route {
            @rabbita.none
          } else {
            @nav.push_url(playground_share_url(reference))
          }
          (next, @rabbita.batch([navigation, request]))
        }
      }
    RouteChanged(url) =>
      match reference_from_route(url.fragment) {
        Err(message) =>
          (
            {
              input: "",
              generation: model.generation + 1,
              view_mode: model.view_mode,
              diff_algorithm: model.diff_algorithm,
              ignore_comments: model.ignore_comments,
              ignore_tests: model.ignore_tests,
              phase: LoadFailed(message),
              route: None,
              share_url: None,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
              review: model.review,
            },
            @rabbita.none,
          )
        Ok(None) =>
          (
            {
              input: "",
              generation: model.generation + 1,
              view_mode: model.view_mode,
              diff_algorithm: model.diff_algorithm,
              ignore_comments: model.ignore_comments,
              ignore_tests: model.ignore_tests,
              phase: Idle,
              route: None,
              share_url: None,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
              review: model.review,
            },
            @rabbita.none,
          )
        Ok(Some(reference)) =>
          if model.route == Some(reference) {
            (model, @rabbita.none)
          } else {
            begin_change_load(model, reference, emit)
          }
      }
    CopyShareLink =>
      if model.share_url is Some(url) {
        (
          model,
          @clipboard.copy(Text(url), copied=emit(ShareCopied), failed=message => {
            emit(ShareCopyFailed(message))
          }),
        )
      } else {
        (model, @rabbita.none)
      }
    ShareCopied =>
      (
        {
          input: model.input,
          generation: model.generation,
          view_mode: model.view_mode,
          diff_algorithm: model.diff_algorithm,
          ignore_comments: model.ignore_comments,
          ignore_tests: model.ignore_tests,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: Copied,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
          review: model.review,
        },
        @rabbita.none,
      )
    ShareCopyFailed(message) =>
      (
        {
          input: model.input,
          generation: model.generation,
          view_mode: model.view_mode,
          diff_algorithm: model.diff_algorithm,
          ignore_comments: model.ignore_comments,
          ignore_tests: model.ignore_tests,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: CopyError(message),
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
          review: model.review,
        },
        @rabbita.none,
      )
    HealthLoaded(result) => {
      let status = match result {
        Ok(response) if response.version == ANALYSIS_VERSION &&
          response.ok &&
          response.openseek_available => BackendReady
        _ => BackendMissing
      }
      (with_backend_status(model, status), @rabbita.none)
    }
    AnalyzeChanges => {
      guard model.backend_status is BackendReady && model.phase is Showing(view) else {
        return (model, @rabbita.none)
      }
      if view.files.length() > MAX_ANALYSIS_FILES {
        return (
          with_analysis_status(
            model,
            AnalysisFailed(
              "This change has more than 50 files and cannot be analyzed in one request.",
            ),
          ),
          @rabbita.none,
        )
      }
      let (prepared_view, source_commands) = prepare_all_sources(
        view,
        model.generation,
        emit,
      )
      let preparing = with_analysis_status(
        with_phase(model, Showing(prepared_view)),
        PreparingSources,
      )
      let (next, analysis_command) = continue_analysis(preparing, emit)
      (next, @rabbita.batch(source_commands..push(analysis_command)))
    }
    ToggleAnalysisGroup(index) =>
      match model.analysis_status {
        AnalysisDone(result, skipped, expanded) =>
          if expanded.get(index) is Some(is_expanded) {
            let changed = expanded.copy()
            changed[index] = !is_expanded
            (
              with_analysis_status(
                model,
                AnalysisDone(result, skipped, changed),
              ),
              @rabbita.none,
            )
          } else {
            (model, @rabbita.none)
          }
        _ => (model, @rabbita.none)
      }
    AnalysisLoaded(generation, result) => {
      if generation != model.generation || !(model.analysis_status is Analyzing) {
        return (model, @rabbita.none)
      }
      match result {
        Err(message) =>
          (with_analysis_status(model, AnalysisFailed(message)), @rabbita.none)
        Ok(response) if response.version == ANALYSIS_VERSION && response.ok => {
          guard model.phase is Showing(view) else {
            return (model, @rabbita.none)
          }
          let skipped = match
            build_analysis_request(
              view,
              model.diff_algorithm,
              ignore_comments=model.ignore_comments,
              ignore_tests=model.ignore_tests,
            ) {
            Ok((_, skipped)) => skipped
            Err(_) => []
          }
          (
            with_analysis_status(
              model,
              AnalysisDone(
                response.analysis,
                skipped,
                initial_group_expansion(response.analysis),
              ),
            ),
            @rabbita.none,
          )
        }
        Ok(_) =>
          (
            with_analysis_status(
              model,
              AnalysisFailed(
                "The analysis service returned an invalid response.",
              ),
            ),
            @rabbita.none,
          )
      }
    }
    PullMetadataLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullMetadata(reference~, attempt=expected_attempt) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(metadata) =>
          start_pull_snapshot(model, reference, attempt, metadata, emit)
      }
    }
    PullCommitMetadataLoaded(generation, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is LoadingPullCommitMetadata(reference~) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(pull) => {
          let repository = branch_repository(
            pull.head,
            reference_repository(reference),
          )
          (
            with_phase(
              model,
              LoadingCommit(reference~, repository~, page=1, first=None, files=[]),
            ),
            commit_request(reference, repository, generation, 1, emit),
          )
        }
      }
    }
    PullCompareLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare=_,
          page~,
          files~
        ) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(compare) =>
          continue_pull_snapshot(
            model,
            reference,
            attempt,
            metadata,
            Some(compare),
            page,
            files,
            emit,
          )
      }
    }
    PullFilesPageLoaded(generation, attempt, page, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare~,
          page=expected_page,
          files~
        ) &&
        attempt == expected_attempt &&
        page == expected_page &&
        page > 0 else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(response) => {
          let accumulated = merge_file_pages(files, response)
          if should_fetch_next_pull_page(
              page,
              response.length(),
              accumulated.length(),
              Some(metadata.changed_files),
            ) {
            (
              with_phase(
                model,
                LoadingPullSnapshot(
                  reference~,
                  attempt~,
                  metadata~,
                  compare~,
                  page=page + 1,
                  files=accumulated,
                ),
              ),
              pull_files_request(reference, generation, attempt, page + 1, emit),
            )
          } else {
            continue_pull_snapshot(
              model, reference, attempt, metadata, compare, 0, accumulated, emit,
            )
          }
        }
      }
    }
    PullValidationLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is ValidatingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare~,
          files~
        ) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(verified) =>
          validate_or_retry_pull_snapshot(
            model, reference, attempt, metadata, compare, files, verified, emit,
          )
      }
    }
    CommitPageLoaded(generation, page, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingCommit(reference~, repository~, page=expected, first~, files~) &&
        page == expected else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(response) => {
          let accumulated = merge_file_pages(files, response.files)
          let first_commit = first.unwrap_or(response)
          if should_fetch_next_page(page, response.files.length()) {
            (
              with_phase(
                model,
                LoadingCommit(
                  reference~,
                  repository~,
                  page=page + 1,
                  first=Some(first_commit),
                  files=accumulated,
                ),
              ),
              commit_request(reference, repository, generation, page + 1, emit),
            )
          } else {
            let (view, command) = finish_commit(
              reference, repository, first_commit, accumulated, generation, emit,
            )
            (
              with_phase(
                model,
                Showing(
                  ensure_expanded_file_documents(
                    view,
                    model.diff_algorithm,
                    ignore_comments=model.ignore_comments,
                    ignore_tests=model.ignore_tests,
                  ),
                ),
              ),
              command,
            )
          }
        }
      }
    }
    ToggleFile(generation, index) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      if file.expanded {
        let changed = {
          file: file.file,
          diff_mode: file.diff_mode,
          expanded: false,
          old_side: file.old_side,
          new_side: file.new_side,
          diff_cache: file.diff_cache,
        }
        (
          with_phase(model, Showing(set_file_state(view, index, changed))),
          @rabbita.none,
        )
      } else {
        let pair = source_pair_for_revisions(
          view.old_revision,
          view.new_revision,
          file.file,
        )
        let first_load = file.old_side is NotRequested ||
          file.new_side is NotRequested
        let changed = {
          file: file.file,
          diff_mode: file.diff_mode,
          expanded: true,
          old_side: if file.old_side is NotRequested {
            initial_side(pair.old_url, true)
          } else {
            file.old_side
          },
          new_side: if file.new_side is NotRequested {
            initial_side(pair.new_url, true)
          } else {
            file.new_side
          },
          diff_cache: file.diff_cache,
        }
        let command = if first_load {
          @rabbita.batch(
            commands_for_file(
              file.file,
              view.old_revision,
              view.new_revision,
              generation,
              index,
              emit,
            ),
          )
        } else {
          @rabbita.none
        }
        (
          with_phase(
            model,
            Showing(
              set_file_state(
                view,
                index,
                ensure_file_document(
                  changed,
                  model.diff_algorithm,
                  ignore_comments=model.ignore_comments,
                  ignore_tests=model.ignore_tests,
                ),
              ),
            ),
          ),
          command,
        )
      }
    }
    RetryFile(generation, index) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      let pair = source_pair_for_revisions(
        view.old_revision,
        view.new_revision,
        file.file,
      )
      let commands : Array[@rabbita.Cmd] = []
      let old_side = if file.old_side is LoadFailed(_) &&
        pair.old_location is Some(location) {
        commands.push(
          gateway_source_request(location, generation, index, Old, emit),
        )
        Loading
      } else {
        file.old_side
      }
      let new_side = if file.new_side is LoadFailed(_) &&
        pair.new_location is Some(location) {
        commands.push(
          gateway_source_request(location, generation, index, New, emit),
        )
        Loading
      } else {
        file.new_side
      }
      let changed = {
        file: file.file,
        diff_mode: file.diff_mode,
        expanded: true,
        old_side,
        new_side,
        diff_cache: empty_diff_cache(),
      }
      (
        with_phase(model, Showing(set_file_state(view, index, changed))),
        @rabbita.batch(commands),
      )
    }
    SourceLoaded(generation, index, side, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      let loaded = side_from_result(result)
      let changed = match side {
        Old =>
          {
            file: file.file,
            diff_mode: file.diff_mode,
            expanded: file.expanded,
            old_side: loaded,
            new_side: file.new_side,
            diff_cache: empty_diff_cache(),
          }
        New =>
          {
            file: file.file,
            diff_mode: file.diff_mode,
            expanded: file.expanded,
            old_side: file.old_side,
            new_side: loaded,
            diff_cache: empty_diff_cache(),
          }
      }
      let changed = if changed.expanded {
        ensure_file_document(
          changed,
          model.diff_algorithm,
          ignore_comments=model.ignore_comments,
          ignore_tests=model.ignore_tests,
        )
      } else {
        changed
      }
      let changed_model = with_phase(
        model,
        Showing(set_file_state(view, index, changed)),
      )
      if model.analysis_status is PreparingSources {
        continue_analysis(changed_model, emit)
      } else {
        (changed_model, @rabbita.none)
      }
    }
  }
}
