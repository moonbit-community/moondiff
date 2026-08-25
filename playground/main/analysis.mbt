///|
const ANALYSIS_VERSION : Int = 1

///|
const MAX_ANALYSIS_FILES : Int = 50

///|
const MAX_ANALYSIS_HUNKS : Int = 200

///|
const MAX_ANALYSIS_PATCH_BYTES : Int = 262_144

///|
priv enum BackendStatus {
  BackendProbing
  BackendReady
  BackendMissing
} derive(Eq)

///|
priv struct HealthResponse {
  version : Int
  ok : Bool
  openseek_available : Bool
} derive(FromJson)

///|
priv struct AnalysisCommitInput {
  owner : String
  repo : String
  sha : String
  parent_sha : Json
  message : String
  html_url : String
} derive(ToJson)

///|
priv struct AnalysisHunkInput {
  id : String
  path : String
  previous_path : Json
  status : String
  patch : String
} derive(ToJson)

///|
priv struct SkippedFile {
  path : String
  reason : String
} derive(Eq, ToJson)

///|
priv struct AnalysisRequest {
  version : Int
  commit : AnalysisCommitInput
  skipped_files : Array[SkippedFile]
  hunks : Array[AnalysisHunkInput]
} derive(ToJson)

///|
priv struct AnalyzedHunk {
  id : String
  explanation : String
} derive(Eq, FromJson)

///|
priv struct AnalysisGroup {
  title : String
  description : String
  hunks : Array[AnalyzedHunk]
} derive(Eq, FromJson)

///|
priv struct AnalysisResult {
  summary : String
  groups : Array[AnalysisGroup]
} derive(Eq, FromJson)

///|
priv struct AnalysisResponse {
  version : Int
  ok : Bool
  analysis : AnalysisResult
} derive(FromJson)

///|
priv struct AnalysisErrorDetail {
  message : String
} derive(FromJson)

///|
priv struct AnalysisErrorResponse {
  error : AnalysisErrorDetail
} derive(FromJson)

///|
priv enum AnalysisStatus {
  AnalysisIdle
  PreparingSources
  Analyzing
  AnalysisDone(AnalysisResult, Array[SkippedFile], Array[Bool])
  AnalysisNoHunks(Array[SkippedFile])
  AnalysisFailed(String)
} derive(Eq)

///|
fn initial_group_expansion(result : AnalysisResult) -> Array[Bool] {
  let expanded : Array[Bool] = []
  for index, _ in result.groups {
    expanded.push(index == 0)
  }
  expanded
}

///|
fn health_request(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @http.get("/api/health").expect_json(result => emit(HealthLoaded(result)))
}

///|
fn analyze_request(
  payload : AnalysisRequest,
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let body = ToJson::to_json(payload).stringify()
  @cmd.custom_cmd(scheduler => {
    send_analysis_request(
      body,
      completed=(ok, status, status_text, response_body) => {
        scheduler.add(
          emit(
            AnalysisLoaded(
              generation,
              decode_analysis_http_response(
                ok, status, status_text, response_body,
              ),
            ),
          ),
        )
      },
      failed=() => {
        scheduler.add(
          emit(
            AnalysisLoaded(
              generation,
              Err(
                "Could not reach the analysis server. Check your connection and try again.",
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
fn decode_analysis_response(body : String) -> AnalysisResponse raise {
  @json.from_json(@json.parse(body))
}

///|
fn decode_analysis_error(body : String) -> AnalysisErrorResponse raise {
  @json.from_json(@json.parse(body))
}

///|
fn decode_analysis_http_response(
  ok : Bool,
  status : Int,
  status_text : String,
  body : String,
) -> Result[AnalysisResponse, String] {
  if ok {
    return try decode_analysis_response(body) catch {
      _ =>
        Err(
          "The analysis server returned an unreadable response. Please retry.",
        )
    } noraise {
      response => Ok(response)
    }
  }
  let suffix = if status_text.trim().is_empty() {
    ""
  } else {
    " \{status_text}"
  }
  let fallback = "The analysis request failed (HTTP \{status}\{suffix}). Please retry."
  try decode_analysis_error(body) catch {
    _ => Err(fallback)
  } noraise {
    response =>
      if response.error.message.trim().is_empty() {
        Err(fallback)
      } else {
        Err(response.error.message)
      }
  }
}

///|
extern "js" fn send_analysis_request(
  body : String,
  completed~ : (Bool, Int, String, String) -> Unit,
  failed~ : () -> Unit,
) =
  #| (body, completed, failed) => {
  #|   fetch("/api/analyze", {
  #|     method: "POST",
  #|     headers: { "Content-Type": "application/json" },
  #|     body,
  #|   })
  #|     .then((response) => response.text().then((responseBody) => {
  #|       completed(response.ok, response.status, response.statusText || "", responseBody);
  #|     }))
  #|     .catch(() => failed());
  #| }

///|
fn mbtdiff_mode(algorithm : DiffAlgorithm) -> @mbtdiff.DiffMode {
  match algorithm {
    LexicalAlgorithm => @mbtdiff.DiffMode::Lexical
    AstAlgorithm => @mbtdiff.DiffMode::Ast
  }
}

///|
fn cached_file_document(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> CachedDiffResult? {
  match file.diff_mode {
    LineDiff => file.diff_cache.line
    MoonBitDiff =>
      match (algorithm, ignore_comments, ignore_tests) {
        (LexicalAlgorithm, false, false) => file.diff_cache.lexical
        (LexicalAlgorithm, true, false) =>
          file.diff_cache.lexical_ignoring_comments
        (LexicalAlgorithm, false, true) =>
          file.diff_cache.lexical_ignoring_tests
        (LexicalAlgorithm, true, true) =>
          file.diff_cache.lexical_ignoring_comments_and_tests
        (AstAlgorithm, false, false) => file.diff_cache.ast
        (AstAlgorithm, true, false) => file.diff_cache.ast_ignoring_comments
        (AstAlgorithm, false, true) => file.diff_cache.ast_ignoring_tests
        (AstAlgorithm, true, true) =>
          file.diff_cache.ast_ignoring_comments_and_tests
      }
  }
}

///|
fn calculate_file_document(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> CachedDiffResult? {
  guard (file.old_side, file.new_side) is (Ready(old), Ready(new)) else {
    return None
  }
  match file.diff_mode {
    LineDiff =>
      Some({
        document: @tokdiff.line_diff(old~, new~, context=3),
        status: Changed,
        fallbacks: [],
      })
    MoonBitDiff => {
      let result = @mbtdiff.diff(
        old.join("\n"),
        new.join("\n"),
        options=@mbtdiff.DiffOptions::new(
          context_lines=3,
          graph_limit=3_000_000,
          ignore_comments~,
          ignore_tests~,
          mode=mbtdiff_mode(algorithm),
        ),
      )
      Some({
        document: result.document(),
        status: result.status(),
        fallbacks: result.fallbacks(),
      })
    }
  }
}

///|
fn ensure_file_document(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> FileState {
  if cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(_) {
    return file
  }
  guard calculate_file_document(
      file,
      algorithm,
      ignore_comments~,
      ignore_tests~,
    )
    is Some(result) else {
    return file
  }
  let cache = match file.diff_mode {
    LineDiff =>
      {
        line: Some(result),
        lexical: file.diff_cache.lexical,
        lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
        lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
        lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
        ast: file.diff_cache.ast,
        ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
        ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
        ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
      }
    MoonBitDiff =>
      match (algorithm, ignore_comments, ignore_tests) {
        (LexicalAlgorithm, false, false) =>
          {
            line: file.diff_cache.line,
            lexical: Some(result),
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (LexicalAlgorithm, true, false) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: Some(result),
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (LexicalAlgorithm, false, true) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: Some(result),
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (LexicalAlgorithm, true, true) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: Some(result),
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (AstAlgorithm, false, false) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: Some(result),
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (AstAlgorithm, true, false) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: Some(result),
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (AstAlgorithm, false, true) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: Some(result),
            ast_ignoring_comments_and_tests: file.diff_cache.ast_ignoring_comments_and_tests,
          }
        (AstAlgorithm, true, true) =>
          {
            line: file.diff_cache.line,
            lexical: file.diff_cache.lexical,
            lexical_ignoring_comments: file.diff_cache.lexical_ignoring_comments,
            lexical_ignoring_tests: file.diff_cache.lexical_ignoring_tests,
            lexical_ignoring_comments_and_tests: file.diff_cache.lexical_ignoring_comments_and_tests,
            ast: file.diff_cache.ast,
            ast_ignoring_comments: file.diff_cache.ast_ignoring_comments,
            ast_ignoring_tests: file.diff_cache.ast_ignoring_tests,
            ast_ignoring_comments_and_tests: Some(result),
          }
      }
  }
  {
    file: file.file,
    diff_mode: file.diff_mode,
    expanded: file.expanded,
    old_side: file.old_side,
    new_side: file.new_side,
    diff_cache: cache,
  }
}

///|
fn ensure_expanded_file_documents(
  view : ChangeView,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> ChangeView {
  let files = view.files.copy()
  for index, file in files {
    if file.expanded {
      files[index] = ensure_file_document(
        file,
        algorithm,
        ignore_comments~,
        ignore_tests~,
      )
    }
  }
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
fn ensure_all_file_documents(
  view : ChangeView,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> ChangeView {
  let files = view.files.copy()
  for index, file in files {
    files[index] = ensure_file_document(
      file,
      algorithm,
      ignore_comments~,
      ignore_tests~,
    )
  }
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
fn file_hunks(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> Array[String] {
  guard cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(result) else {
    return []
  }
  @unified.render_unified_hunks(result.document)
}

///|
fn non_text_reason(file : FileState) -> String? {
  match file.old_side {
    CannotRender(message, true) => return Some(message)
    _ => ()
  }
  match file.new_side {
    CannotRender(message, true) => Some(message)
    _ => None
  }
}

///|
fn blocking_source_problem(file : FileState) -> String? {
  match file.old_side {
    LoadFailed(message) | CannotRender(message, false) => return Some(message)
    _ => ()
  }
  match file.new_side {
    LoadFailed(message) | CannotRender(message, false) => Some(message)
    _ => None
  }
}

///|
fn sources_pending(view : ChangeView) -> Bool {
  for file in view.files {
    if file.old_side is (NotRequested | Loading) ||
      file.new_side is (NotRequested | Loading) {
      return true
    }
  }
  false
}

///|
fn ignored_change_subject(
  ignore_comments : Bool,
  ignore_tests : Bool,
) -> String {
  if ignore_comments && ignore_tests {
    "MoonBit test blocks, comments, or blank lines"
  } else if ignore_tests {
    "MoonBit test blocks"
  } else {
    "comments or blank lines"
  }
}

///|
fn ignored_filter_action(ignore_comments : Bool, ignore_tests : Bool) -> String {
  if ignore_comments && ignore_tests {
    "turn off Ignore tests or Ignore comments to include the corresponding filtered changes"
  } else if ignore_tests {
    "turn off Ignore tests to include test changes"
  } else {
    "turn off Ignore comments to include comment and blank-line changes"
  }
}

///|
fn build_analysis_request(
  view : ChangeView,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> Result[(AnalysisRequest, Array[SkippedFile]), String] {
  let hunks : Array[AnalysisHunkInput] = []
  let skipped : Array[SkippedFile] = []
  let mut patch_bytes = 0
  for file_index, state in view.files {
    if blocking_source_problem(state) is Some(message) {
      return Err("Could not prepare \{state.file.filename}: \{message}")
    }
    if non_text_reason(state) is Some(reason) {
      skipped.push({ path: state.file.filename, reason })
      continue
    }
    guard cached_file_document(
        state,
        algorithm,
        ignore_comments~,
        ignore_tests~,
      )
      is Some(diff) else {
      return Err(
        "Could not prepare \{state.file.filename}: diff is unavailable",
      )
    }
    if state.diff_mode is MoonBitDiff && diff.status is IgnoredOnly {
      let structural = if algorithm is AstAlgorithm {
        "structural "
      } else {
        ""
      }
      skipped.push({
        path: state.file.filename,
        reason: "No \{structural}changes besides \{ignored_change_subject(ignore_comments, ignore_tests)} were found; \{ignored_filter_action(ignore_comments, ignore_tests)}.",
      })
      continue
    }
    if state.diff_mode is MoonBitDiff &&
      algorithm is AstAlgorithm &&
      diff.status is (Identical | NoStructuralChanges) {
      skipped.push({
        path: state.file.filename,
        reason: "No structural changes were found; switch to Lexical to analyze text changes.",
      })
      continue
    }
    for
      hunk_index, patch in file_hunks(
        state,
        algorithm,
        ignore_comments~,
        ignore_tests~,
      ) {
      patch_bytes += @utf8.encode(patch).length()
      if hunks.length() + 1 > MAX_ANALYSIS_HUNKS {
        return Err(
          "This change has more than 200 text hunks and cannot be analyzed in one request.",
        )
      }
      if patch_bytes > MAX_ANALYSIS_PATCH_BYTES {
        return Err("The unified patches exceed the 256 KiB analysis limit.")
      }
      hunks.push({
        id: "f\{file_index}-h\{hunk_index}",
        path: state.file.filename,
        previous_path: if state.file.previous_filename is Some(path) {
          Json::string(path)
        } else {
          Json::null()
        },
        status: state.file.status,
        patch,
      })
    }
  }
  let payload = AnalysisRequest::{
    version: ANALYSIS_VERSION,
    commit: {
      owner: view.reference.owner,
      repo: view.reference.repo,
      sha: view.sha,
      parent_sha: if view.parent_sha is Some(parent) {
        Json::string(parent)
      } else {
        Json::null()
      },
      message: view.message,
      html_url: view.html_url,
    },
    skipped_files: skipped,
    hunks,
  }
  Ok((payload, skipped))
}

///|
fn analysis_note(
  result : AnalysisResult,
  file_index : Int,
  hunk_index : Int,
) -> @render_html.HunkNote? {
  let id = "f\{file_index}-h\{hunk_index}"
  for group in result.groups {
    for hunk in group.hunks {
      if hunk.id == id {
        return Some({ title: group.title, body: hunk.explanation })
      }
    }
  }
  None
}

///|
fn notes_for_file(
  result : AnalysisResult,
  file_index : Int,
  hunk_count : Int,
) -> Array[@render_html.HunkNote?] {
  let notes : Array[@render_html.HunkNote?] = []
  for hunk_index in 0..<hunk_count {
    notes.push(analysis_note(result, file_index, hunk_index))
  }
  notes
}
