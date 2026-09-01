///|
priv enum ViewMode {
  Split
  Unified
} derive(Eq)

///|
priv enum DiffAlgorithm {
  LexicalAlgorithm
  AstAlgorithm
} derive(Eq, Hash)

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
priv enum CachedDiffResult {
  Line(@mbtdiff.HunkDocument)
  MoonBit(document~ : @mbtdiff.DiffDocument, status~ : @mbtdiff.DiffStatus)
} derive(Eq)

///|
priv enum CacheKey {
  Line
  MoonBit(DiffAlgorithm, Bool, Bool)
} derive(Eq, Hash)

///|
priv struct DiffCache {
  entries : @immut_hashmap.HashMap[CacheKey, CachedDiffResult]
} derive(Eq)

///|
fn DiffCache::empty() -> DiffCache {
  { entries: @immut_hashmap.new(), }
}

///|
fn DiffCache::get(self : DiffCache, key : CacheKey) -> CachedDiffResult? {
  self.entries.get(key)
}

///|
fn DiffCache::put(
  self : DiffCache,
  key : CacheKey,
  value : CachedDiffResult,
) -> DiffCache {
  { entries: self.entries.add(key, value), }
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
    review: initial_review_state(),
  }
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
    result => emit(Load(CommitPageLoaded(generation, page, result))),
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
    result => emit(Load(PullCommitMetadataLoaded(generation, result))),
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
    result => emit(Load(PullMetadataLoaded(generation, attempt, result))),
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
    result => emit(Load(PullCompareLoaded(generation, attempt, result))),
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
    result => emit(Load(PullFilesPageLoaded(generation, attempt, page, result))),
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
    result => emit(Load(PullValidationLoaded(generation, attempt, result))),
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
      diff_cache: DiffCache::empty(),
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
  { ..view, files, }
}

///|
fn with_phase(model : Model, phase : Phase) -> Model {
  { ..model, phase, }
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
      ..model,
      input: canonical_github_url(reference),
      generation,
      phase,
      route: Some(reference),
      share_url: Some(playground_share_url(reference)),
      copy_status: CopyReady,
      review: if extension_host_enabled() {
        { auth: model.review.auth, comments: CommentsLoading, draft: None, }
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
    (next, command)
  }
}

///|
fn app_subscriptions(_model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  if extension_host_enabled() {
    @sub.batch([
      @sub.on_url_changed(url => emit(Ui(RouteChanged(url)))),
      @sub.on_visibility_change(hidden => {
        emit(Review(VisibilityChanged(hidden)))
      }),
    ])
  } else {
    @sub.on_url_changed(url => emit(Ui(RouteChanged(url))))
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
