// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

///|
priv enum ViewMode {
  Split
  Unified
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
priv struct FileState {
  file : ApiFile
  diff_mode : FileDiffMode
  expanded : Bool
  old_side : SideLoad
  new_side : SideLoad
} derive(Eq)

///|
priv struct CommitView {
  reference : CommitRef
  sha : String
  parent_sha : String?
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
    page~ : Int,
    first~ : ApiCommit?,
    files~ : Array[ApiFile]
  )
  LoadFailed(String)
  Showing(CommitView)
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
  phase : Phase
  route : CommitRef?
  share_url : String?
  copy_status : CopyStatus
  backend_status : BackendStatus
  analysis_status : AnalysisStatus
} derive(Eq)

///|
fn initial_model() -> Model {
  {
    input: "",
    generation: 0,
    view_mode: Split,
    phase: Idle,
    route: None,
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendProbing,
    analysis_status: AnalysisIdle,
  }
}

///|
priv enum Msg {
  InputChanged(String)
  Submit
  RouteChanged(@url.Url)
  ToggleView
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
}

///|
fn error_message(error : Error, api : Bool) -> String {
  let detail = error.to_string()
  if api && detail.contains("HTTP 403") {
    "GitHub rejected the request (HTTP 403). The anonymous API limit may be exhausted; try again later."
  } else if api && detail.contains("HTTP 404") {
    "GitHub could not find that public repository or commit."
  } else {
    detail
  }
}

///|
fn commit_request(
  reference : CommitRef,
  generation : Int,
  page : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @http.get(commit_api_url(reference, page)).expect_json(result => {
    emit(CommitPageLoaded(generation, page, result))
  })
}

///|
fn source_request(
  url : String,
  generation : Int,
  index : Int,
  side : SourceSide,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @http.get(url).expect_bytes(result => {
    emit(SourceLoaded(generation, index, side, result))
  })
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
  reference : CommitRef,
  sha : String,
  parent_sha : String?,
  generation : Int,
  index : Int,
  emit : @rabbita.Emit[Msg],
) -> Array[@rabbita.Cmd] {
  let pair = source_pair(reference, sha, parent_sha, file)
  let commands : Array[@rabbita.Cmd] = []
  if pair.old_url is Some(url) {
    commands.push(source_request(url, generation, index, Old, emit))
  }
  if pair.new_url is Some(url) {
    commands.push(source_request(url, generation, index, New, emit))
  }
  commands
}

///|
fn finish_commit(
  reference : CommitRef,
  first : ApiCommit,
  all_files : Array[ApiFile],
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> (CommitView, @rabbita.Cmd) {
  let parent_sha = first_parent(first)
  let states : Array[FileState] = []
  let commands : Array[@rabbita.Cmd] = []
  let mut moonbit_file_count = 0
  for index, file in all_files {
    let diff_mode = file_diff_mode(file)
    let expanded = diff_mode is MoonBitDiff && moonbit_file_count < 20
    if diff_mode is MoonBitDiff {
      moonbit_file_count += 1
    }
    let pair = source_pair(reference, first.sha, parent_sha, file)
    states.push({
      file,
      diff_mode,
      expanded,
      old_side: initial_side(pair.old_url, expanded),
      new_side: initial_side(pair.new_url, expanded),
    })
    if expanded {
      for
        command in commands_for_file(
          file,
          reference,
          first.sha,
          parent_sha,
          generation,
          index,
          emit,
        ) {
        commands.push(command)
      }
    }
  }
  (
    {
      reference,
      sha: first.sha,
      parent_sha,
      message: first.commit.message,
      html_url: first.html_url,
      stats: first.stats,
      total_files: all_files.length(),
      files: states,
    },
    @rabbita.batch(commands),
  )
}

///|
fn set_file_state(
  view : CommitView,
  index : Int,
  state : FileState,
) -> CommitView {
  let files = view.files.copy()
  files[index] = state
  {
    reference: view.reference,
    sha: view.sha,
    parent_sha: view.parent_sha,
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
    phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status: model.backend_status,
    analysis_status: model.analysis_status,
  }
}

///|
fn with_backend_status(model : Model, backend_status : BackendStatus) -> Model {
  {
    input: model.input,
    generation: model.generation,
    view_mode: model.view_mode,
    phase: model.phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status,
    analysis_status: model.analysis_status,
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
    phase: model.phase,
    route: model.route,
    share_url: model.share_url,
    copy_status: model.copy_status,
    backend_status: model.backend_status,
    analysis_status,
  }
}

///|
fn begin_commit_load(
  model : Model,
  reference : CommitRef,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let generation = model.generation + 1
  (
    {
      input: canonical_github_url(reference),
      generation,
      view_mode: model.view_mode,
      phase: LoadingCommit(reference~, page=1, first=None, files=[]),
      route: Some(reference),
      share_url: Some(playground_share_url(reference)),
      copy_status: CopyReady,
      backend_status: model.backend_status,
      analysis_status: AnalysisIdle,
    },
    commit_request(reference, generation, 1, emit),
  )
}

///|
fn app_init(emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  let model = initial_model()
  let (next, command) = match
    reference_from_playground_url(browser_current_url()) {
    Ok(Some(reference)) => begin_commit_load(model, reference, emit)
    Ok(None) => (model, @rabbita.none)
    Err(message) => (with_phase(model, LoadFailed(message)), @rabbita.none)
  }
  (next, @rabbita.batch([health_request(emit), command]))
}

///|
fn app_subscriptions(_model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  @sub.on_url_changed(url => emit(RouteChanged(url)))
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
  view : CommitView,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> (CommitView, Array[@rabbita.Cmd]) {
  let files = view.files.copy()
  let commands : Array[@rabbita.Cmd] = []
  for index, file in files {
    let pair = source_pair(view.reference, view.sha, view.parent_sha, file.file)
    let old_side = match (file.old_side, pair.old_url) {
      (NotRequested | LoadFailed(_), Some(url)) => {
        commands.push(source_request(url, generation, index, Old, emit))
        Loading
      }
      (side, _) => side
    }
    let new_side = match (file.new_side, pair.new_url) {
      (NotRequested | LoadFailed(_), Some(url)) => {
        commands.push(source_request(url, generation, index, New, emit))
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
    }
  }
  (
    {
      reference: view.reference,
      sha: view.sha,
      parent_sha: view.parent_sha,
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
  match build_analysis_request(view) {
    Err(message) =>
      (with_analysis_status(model, AnalysisFailed(message)), @rabbita.none)
    Ok((payload, _)) =>
      (
        with_analysis_status(model, Analyzing),
        analyze_request(payload, model.generation, emit),
      )
  }
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    InputChanged(value) =>
      (
        {
          input: value,
          generation: model.generation,
          view_mode: model.view_mode,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: CopyReady,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
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
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: model.copy_status,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
        },
        @rabbita.none,
      )
    Submit =>
      match parse_commit_url(model.input) {
        Err(message) =>
          (
            {
              input: model.input,
              generation: model.generation + 1,
              view_mode: model.view_mode,
              phase: LoadFailed(message),
              route: model.route,
              share_url: model.share_url,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
            },
            @rabbita.none,
          )
        Ok(reference) => {
          let already_at_route = model.route == Some(reference)
          let (next, request) = begin_commit_load(model, reference, emit)
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
              phase: LoadFailed(message),
              route: None,
              share_url: None,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
            },
            @rabbita.none,
          )
        Ok(None) =>
          (
            {
              input: "",
              generation: model.generation + 1,
              view_mode: model.view_mode,
              phase: Idle,
              route: None,
              share_url: None,
              copy_status: CopyReady,
              backend_status: model.backend_status,
              analysis_status: AnalysisIdle,
            },
            @rabbita.none,
          )
        Ok(Some(reference)) =>
          if model.route == Some(reference) {
            (model, @rabbita.none)
          } else {
            begin_commit_load(model, reference, emit)
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
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: Copied,
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
        },
        @rabbita.none,
      )
    ShareCopyFailed(message) =>
      (
        {
          input: model.input,
          generation: model.generation,
          view_mode: model.view_mode,
          phase: model.phase,
          route: model.route,
          share_url: model.share_url,
          copy_status: CopyError(message),
          backend_status: model.backend_status,
          analysis_status: model.analysis_status,
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
              "This commit has more than 50 files and cannot be analyzed in one request.",
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
          let skipped = match build_analysis_request(view) {
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
    CommitPageLoaded(generation, page, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingCommit(reference~, page=expected, first~, files~) &&
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
                  page=page + 1,
                  first=Some(first_commit),
                  files=accumulated,
                ),
              ),
              commit_request(reference, generation, page + 1, emit),
            )
          } else {
            let (view, command) = finish_commit(
              reference, first_commit, accumulated, generation, emit,
            )
            (with_phase(model, Showing(view)), command)
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
        }
        (
          with_phase(model, Showing(set_file_state(view, index, changed))),
          @rabbita.none,
        )
      } else {
        let pair = source_pair(
          view.reference,
          view.sha,
          view.parent_sha,
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
        }
        let command = if first_load {
          @rabbita.batch(
            commands_for_file(
              file.file,
              view.reference,
              view.sha,
              view.parent_sha,
              generation,
              index,
              emit,
            ),
          )
        } else {
          @rabbita.none
        }
        (
          with_phase(model, Showing(set_file_state(view, index, changed))),
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
      let pair = source_pair(
        view.reference,
        view.sha,
        view.parent_sha,
        file.file,
      )
      let commands : Array[@rabbita.Cmd] = []
      let old_side = if file.old_side is LoadFailed(_) &&
        pair.old_url is Some(url) {
        commands.push(source_request(url, generation, index, Old, emit))
        Loading
      } else {
        file.old_side
      }
      let new_side = if file.new_side is LoadFailed(_) &&
        pair.new_url is Some(url) {
        commands.push(source_request(url, generation, index, New, emit))
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
          }
        New =>
          {
            file: file.file,
            diff_mode: file.diff_mode,
            expanded: file.expanded,
            old_side: file.old_side,
            new_side: loaded,
          }
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
