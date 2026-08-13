// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

///|
extern "js" fn read_fixture(path : String) -> String =
  #| (path) => require("node:fs").readFileSync(path, "utf8")

///|
fn fixture_file(
  filename : String,
  status : String,
  previous_filename? : String,
) -> ApiFile {
  {
    filename,
    previous_filename,
    status,
    additions: 1,
    deletions: 2,
    changes: 3,
  }
}

///|
test "parse supported GitHub commit URL forms" {
  guard parse_commit_url(
      "https://github.com/moonbit-community/moondiff/commit/aBcDeF1?diff=split#files",
    )
    is Ok(commit) else {
    fail("expected commit URL to parse")
  }
  assert_eq(commit.owner, "moonbit-community")
  assert_eq(commit.repo, "moondiff")
  assert_eq(commit.sha, "aBcDeF1")

  guard parse_commit_url(
      "https://github.com/moonbitlang/core/pull/42/changes/0123456789abcdef",
    )
    is Ok(pr) else {
    fail("expected PR changes URL to parse")
  }
  assert_eq(pr.owner, "moonbitlang")
  assert_eq(pr.repo, "core")
  assert_eq(pr.sha, "0123456789abcdef")
}

///|
test "shared playground routes round-trip to canonical GitHub commit URLs" {
  let reference = CommitRef::{
    owner: "moonbit-community",
    repo: "moondiff",
    sha: "aBcDeF1",
  }
  assert_eq(
    playground_route(reference),
    "#/moonbit-community/moondiff/commit/aBcDeF1",
  )
  assert_eq(
    canonical_github_url(reference),
    "https://github.com/moonbit-community/moondiff/commit/aBcDeF1",
  )
  guard reference_from_playground_url(
      "https://example.github.io/moondiff/#/moonbit-community/moondiff/commit/aBcDeF1",
    )
    is Ok(Some(parsed)) else {
    fail("expected the shared route to parse")
  }
  assert_true(parsed == reference)
  assert_true(
    reference_from_playground_url("https://example.com/moondiff/") is Ok(None),
  )
  assert_true(
    reference_from_playground_url(
      "https://example.com/moondiff/#/moonbit-community/moondiff/pull/1",
    )
    is Err(_),
  )
  assert_true(
    reference_from_playground_url(
      "https://example.com/moondiff/#/bad owner/moondiff/commit/abcdef1",
    )
    is Err(_),
  )
}

///|
test "reject unsupported or malformed URLs" {
  for
    url in [
      "http://github.com/a/b/commit/abcdef1", "https://git.example.com/a/b/commit/abcdef1",
      "https://github.example.com/a/b/commit/abcdef1", "https://github.com/a/b/pull/1/files",
      "https://github.com/a/b/compare/abcdef1...abcdef2", "https://github.com/-bad/b/commit/abcdef1",
      "https://github.com/a/bad%2Frepo/commit/abcdef1", "https://github.com/a/b/commit/abcdef",
      "https://github.com/a/b/pull/nope/changes/abcdef1", "https://github.com/a/b/pull/0/changes/abcdef1",
      "https://github.com:443/a/b/commit/abcdef1",
    ] {
    assert_true(parse_commit_url(url) is Err(_), msg=url)
  }
}

///|
test "select MoonBit diff only when either path ends with lowercase mbt" {
  for
    file in [
      fixture_file("main.mbt", "modified"),
      fixture_file("new.txt", "renamed", previous_filename="old.mbt"),
      fixture_file("new.mbt", "renamed", previous_filename="old.txt"),
    ] {
    assert_true(file_diff_mode(file) is MoonBitDiff, msg=file.filename)
  }
  for
    file in [
      fixture_file("README.md", "modified"),
      fixture_file("types.mbti", "modified"),
      fixture_file("guide.mbt.md", "modified"),
      fixture_file("MAIN.MBT", "modified"),
      fixture_file("moon.pkg", "modified"),
      fixture_file("new.txt", "renamed", previous_filename="old.txt"),
    ] {
    assert_true(file_diff_mode(file) is LineDiff, msg=file.filename)
  }
}

///|
test "diff notices distinguish whole-file and partial lexical fallbacks" {
  guard diff_notice(@alignment.AlignedDiffOutcome::Fallback("old: parse error"))
    is Some(complete) else {
    fail("expected a complete fallback notice")
  }
  assert_eq(complete.class_name, "diff-notice fallback")
  assert_eq(complete.label, "Lexical fallback")
  assert_true(complete.message.contains("this entire file"))
  assert_true(complete.message.contains("old: parse error"))

  guard diff_notice(
      @alignment.AlignedDiffOutcome::PartialFallback([
        "graph limit exceeded (3000000) at old line 724, new line 768",
      ]),
    )
    is Some(partial) else {
    fail("expected a partial fallback notice")
  }
  assert_eq(partial.class_name, "diff-notice partial-fallback")
  assert_eq(partial.label, "Partial lexical fallback")
  assert_true(partial.message.contains("AST diff was used for the rest"))
  assert_true(partial.message.contains("old line 724, new line 768"))

  assert_true(diff_notice(@alignment.AlignedDiffOutcome::Rendered) is None)
  assert_true(
    diff_notice(@alignment.AlignedDiffOutcome::NoStructuralChanges) is None,
  )
}

///|
test "raw content URLs percent-encode each path byte" {
  let reference = CommitRef::{
    owner: "moonbit-community",
    repo: "moondiff",
    sha: "abcdef1",
  }
  assert_eq(
    raw_url(reference, "abcdef1", "src/a b#中?.mbt"),
    "https://raw.githubusercontent.com/moonbit-community/moondiff/abcdef1/src/a%20b%23%E4%B8%AD%3F.mbt",
  )
}

///|
test "decode local GitHub fixtures and select the first merge parent" {
  let merge = decode_commit(
    read_fixture("playground/main/fixtures/commit_page1.json"),
  )
  assert_eq(merge.sha, "abcdef1234567890abcdef1234567890abcdef12")
  assert_eq(
    merge.commit.message,
    "Add playground\n\nRender public MoonBit commits.",
  )
  assert_eq(
    first_parent(merge),
    Some("1111111111111111111111111111111111111111"),
  )
  assert_eq(merge.files.length(), 3)
  assert_eq(merge.files[0].previous_filename, None)
  assert_eq(merge.files[1].previous_filename, Some("src/old_name.txt"))

  let root = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  assert_eq(first_parent(root), None)
  assert_eq(root.stats.additions, 2)
}

///|
test "pagination appends file metadata and stops at GitHub's 30-page cap" {
  let first = [fixture_file("a.mbt", "modified")]
  let second = [fixture_file("b.mbt", "added")]
  let merged = merge_file_pages(first, second)
  assert_eq(merged.map(file => file.filename), ["a.mbt", "b.mbt"])
  assert_true(should_fetch_next_page(1, 100))
  assert_false(should_fetch_next_page(1, 99))
  assert_false(should_fetch_next_page(30, 100))
  assert_true(
    commit_api_url({ owner: "a", repo: "b", sha: "abcdef1" }, 30).has_suffix(
      "?per_page=100&page=30",
    ),
  )
}

///|
test "added deleted renamed merge and root commits choose the correct raw sides" {
  let reference = CommitRef::{ owner: "owner", repo: "repo", sha: "abcdef1" }
  let parent = Some("1111111")
  let added = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("new.mbt", "added"),
  )
  assert_eq(added.old_url, None)
  assert_true(added.new_url is Some(_))

  let deleted = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("old.mbt", "removed"),
  )
  assert_true(deleted.old_url is Some(_))
  assert_eq(deleted.new_url, None)

  let renamed = source_pair(
    reference,
    "2222222",
    parent,
    fixture_file("new.mbt", "renamed", previous_filename="old name.mbt"),
  )
  assert_true(renamed.old_url.unwrap().has_suffix("/old%20name.mbt"))
  assert_true(renamed.new_url.unwrap().has_suffix("/new.mbt"))

  let root = source_pair(
    reference,
    "2222222",
    None,
    fixture_file("main.mbt", "modified"),
  )
  assert_eq(root.old_url, None)
  assert_true(root.new_url is Some(_))
}

///|
test "source validation accepts Unicode and normalizes CRLF" {
  guard check_source(@utf8.encode("a\r\n名😀\r\n")) is Renderable(lines) else {
    fail("expected source to render")
  }
  assert_eq(lines, ["a", "名😀", ""])
}

///|
test "source validation rejects invalid UTF-8, NUL, byte and line limits" {
  guard check_source([0xff]) is Rejected(invalid_utf8, true) else {
    fail("expected invalid UTF-8 to be rejected")
  }
  assert_true(invalid_utf8.contains("not valid UTF-8"))
  guard check_source(b"a\x00b") is Rejected(nul, true) else {
    fail("expected NUL to be rejected")
  }
  assert_true(nul.contains("NUL byte"))
  assert_true(
    check_source(Bytes::make(MAX_SOURCE_BYTES + 1, b'x')) is Rejected(_, false),
  )
  assert_true(
    check_source(@utf8.encode("\n".repeat(MAX_SOURCE_LINES)))
    is Rejected(_, false),
  )
}

///|
test "stale commit responses are discarded by generation" {
  let model = Model::{
    input: "https://github.com/a/b/commit/abcdef1",
    generation: 2,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    phase: Idle,
    route: None,
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendMissing,
    analysis_status: AnalysisIdle,
  }
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update(model, CommitPageLoaded(1, 1, Ok(fixture)), emit)
  assert_true(after == model)
}

///|
test "all files remain listed but only the first twenty MoonBit diffs auto-load" {
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  let files : Array[ApiFile] = []
  files.push(fixture_file("README.md", "added"))
  for index in 0..<21 {
    if index == 5 {
      files.push(
        fixture_file(
          "src/file_5.txt",
          "renamed",
          previous_filename="src/file_5.mbt",
        ),
      )
    } else {
      files.push(fixture_file("src/file_\{index}.mbt", "added"))
    }
    if index == 9 {
      files.push(fixture_file("assets/logo.bin", "added"))
    }
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let reference = CommitRef::{
    owner: "example",
    repo: "root",
    sha: fixture.sha,
  }
  let (view, _) = finish_commit(reference, fixture, files, 7, emit)
  assert_eq(view.files.length(), files.length())
  assert_eq(
    view.files.map(state => state.file.filename),
    files.map(file => file.filename),
  )
  let mut moonbit_index = 0
  for state in view.files {
    match state.diff_mode {
      MoonBitDiff => {
        if moonbit_index < 20 {
          assert_true(state.expanded, msg=state.file.filename)
          assert_true(state.old_side is Ready([]), msg=state.file.filename)
          assert_true(state.new_side is Loading, msg=state.file.filename)
        } else {
          assert_false(state.expanded, msg=state.file.filename)
          assert_true(state.new_side is NotRequested, msg=state.file.filename)
        }
        moonbit_index += 1
      }
      LineDiff => {
        assert_false(state.expanded, msg=state.file.filename)
        assert_true(state.new_side is NotRequested, msg=state.file.filename)
      }
    }
  }
  assert_eq(moonbit_index, 21)

  let model = Model::{
    input: "",
    generation: 7,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    phase: Showing(view),
    route: Some(reference),
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendMissing,
    analysis_status: AnalysisIdle,
  }
  let (after, _) = update(
    model,
    SourceLoaded(6, 0, New, Ok(("text/plain", @utf8.encode("stale")))),
    emit,
  )
  assert_true(after == model)
}

///|
fn analysis_test_view(files : Array[ApiFile]) -> CommitView raise {
  let fixture = decode_commit(
    read_fixture("playground/main/fixtures/commit_page1.json"),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (view, _) = finish_commit(
    { owner: "example", repo: "project", sha: fixture.sha },
    fixture,
    files,
    9,
    emit,
  )
  view
}

///|
fn analysis_test_model(
  view : CommitView,
  status? : AnalysisStatus = AnalysisIdle,
) -> Model {
  {
    input: "",
    generation: 9,
    view_mode: Split,
    diff_algorithm: LexicalAlgorithm,
    phase: Showing(view),
    route: Some(view.reference),
    share_url: None,
    copy_status: CopyReady,
    backend_status: BackendReady,
    analysis_status: status,
  }
}

///|
test "analysis prepares every source without expanding lazy file cards" {
  let view = analysis_test_view([
    fixture_file("README.md", "modified"),
    fixture_file("docs/guide.txt", "modified"),
  ])
  assert_true(view.files.all(file => !file.expanded))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update(analysis_test_model(view), AnalyzeChanges, emit)
  assert_true(after.analysis_status is PreparingSources)
  guard after.phase is Showing(prepared) else {
    fail("expected prepared commit")
  }
  for file in prepared.files {
    assert_false(file.expanded)
    assert_true(file.old_side is Loading)
    assert_true(file.new_side is Loading)
  }
}

///|
test "analysis rejects file and source limits before making a partial conclusion" {
  let files : Array[ApiFile] = []
  for index in 0..<51 {
    files.push(fixture_file("file-\{index}.txt", "modified"))
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (too_many, _) = update(
    analysis_test_model(analysis_test_view(files)),
    AnalyzeChanges,
    emit,
  )
  guard too_many.analysis_status is AnalysisFailed(file_message) else {
    fail("expected file limit failure")
  }
  assert_true(file_message.contains("more than 50 files"))

  let limited_view = set_file_state(
    analysis_test_view([fixture_file("large.txt", "modified")]),
    0,
    {
      file: fixture_file("large.txt", "modified"),
      diff_mode: LineDiff,
      expanded: false,
      old_side: CannotRender(
        "Cannot render: one side is larger than 1 MiB.", false,
      ),
      new_side: Ready(["new"]),
      diff_cache: empty_diff_cache(),
    },
  )
  let (limited, _) = update(
    analysis_test_model(limited_view),
    AnalyzeChanges,
    emit,
  )
  guard limited.analysis_status is AnalysisFailed(source_message) else {
    fail("expected source limit failure")
  }
  assert_true(source_message.contains("larger than 1 MiB"))

  let patch_file = fixture_file("patch.txt", "modified")
  let patch_view = set_file_state(analysis_test_view([patch_file]), 0, {
    file: patch_file,
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["a".repeat(MAX_ANALYSIS_PATCH_BYTES)]),
    new_side: Ready(["b".repeat(MAX_ANALYSIS_PATCH_BYTES)]),
    diff_cache: empty_diff_cache(),
  })
  let patch_view = ensure_all_file_documents(patch_view, LexicalAlgorithm)
  guard build_analysis_request(patch_view, LexicalAlgorithm)
    is Err(patch_message) else {
    fail("expected patch byte limit failure")
  }
  assert_true(patch_message.contains("256 KiB"))

  let old : Array[String] = []
  let new : Array[String] = []
  for index in 0..<201 {
    old.push("old-\{index}")
    new.push("new-\{index}")
    for context in 0..<7 {
      let line = "context-\{index}-\{context}"
      old.push(line)
      new.push(line)
    }
  }
  let hunk_file = fixture_file("hunks.txt", "modified")
  let hunk_view = set_file_state(analysis_test_view([hunk_file]), 0, {
    file: hunk_file,
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: empty_diff_cache(),
  })
  let hunk_view = ensure_all_file_documents(hunk_view, LexicalAlgorithm)
  guard build_analysis_request(hunk_view, LexicalAlgorithm) is Err(hunk_message) else {
    fail("expected hunk count limit failure")
  }
  assert_true(hunk_message.contains("more than 200 text hunks"))
}

///|
test "non-text files are skipped while text hunk ids retain file indexes" {
  let files = [
    fixture_file("src/a.txt", "modified"),
    fixture_file("assets/logo.bin", "modified"),
    fixture_file("src/c.txt", "modified"),
  ]
  let mut view = analysis_test_view(files)
  view = set_file_state(view, 0, {
    file: files[0],
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["old"]),
    new_side: Ready(["new"]),
    diff_cache: empty_diff_cache(),
  })
  view = set_file_state(view, 1, {
    file: files[1],
    diff_mode: LineDiff,
    expanded: false,
    old_side: CannotRender(
      "Cannot render: the file is binary or is not valid UTF-8.", true,
    ),
    new_side: CannotRender(
      "Cannot render: the file is binary or is not valid UTF-8.", true,
    ),
    diff_cache: empty_diff_cache(),
  })
  view = set_file_state(view, 2, {
    file: files[2],
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["before"]),
    new_side: Ready(["after"]),
    diff_cache: empty_diff_cache(),
  })
  view = ensure_all_file_documents(view, LexicalAlgorithm)
  guard build_analysis_request(view, LexicalAlgorithm) is Ok((payload, skipped)) else {
    fail("expected analysis request")
  }
  assert_eq(payload.hunks.map(hunk => hunk.id), ["f0-h0", "f2-h0"])
  assert_eq(skipped.map(file => file.path), ["assets/logo.bin"])
  let encoded = ToJson::to_json(payload).stringify()
  assert_true(encoded.contains("\"previous_path\":null"))
  assert_true(encoded.contains("\"skipped_files\":["))

  let root = decode_commit(
    read_fixture("playground/main/fixtures/root_commit.json"),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (root_view, _) = finish_commit(
    { owner: "example", repo: "root", sha: root.sha },
    root,
    [fixture_file("root.txt", "added")],
    9,
    emit,
  )
  let root_ready = set_file_state(root_view, 0, {
    file: fixture_file("root.txt", "added"),
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready([]),
    new_side: Ready(["root"]),
    diff_cache: empty_diff_cache(),
  })
  let root_ready = ensure_all_file_documents(root_ready, LexicalAlgorithm)
  guard build_analysis_request(root_ready, LexicalAlgorithm)
    is Ok((root_payload, _)) else {
    fail("expected root analysis request")
  }
  assert_true(
    ToJson::to_json(root_payload).stringify().contains("\"parent_sha\":null"),
  )

  let renamed = fixture_file("new.txt", "renamed", previous_filename="old.txt")
  let renamed_view = set_file_state(analysis_test_view([renamed]), 0, {
    file: renamed,
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["old"]),
    new_side: Ready(["new"]),
    diff_cache: empty_diff_cache(),
  })
  let renamed_view = ensure_all_file_documents(renamed_view, LexicalAlgorithm)
  guard build_analysis_request(renamed_view, LexicalAlgorithm)
    is Ok((renamed_payload, _)) else {
    fail("expected renamed analysis request")
  }
  let renamed_json = ToJson::to_json(renamed_payload).stringify()
  assert_true(renamed_json.contains("\"previous_path\":\"old.txt\""))
  assert_true(renamed_json.contains("\"status\":\"renamed\""))
}

///|
test "failed source preparation retries and advances only after all sides load" {
  let file = fixture_file("README.md", "modified")
  let view = set_file_state(analysis_test_view([file]), 0, {
    file,
    diff_mode: LineDiff,
    expanded: false,
    old_side: LoadFailed("temporary failure"),
    new_side: Ready(["new"]),
    diff_cache: empty_diff_cache(),
  })
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (retrying, _) = update(analysis_test_model(view), AnalyzeChanges, emit)
  assert_true(retrying.analysis_status is PreparingSources)
  guard retrying.phase is Showing(preparing) else {
    fail("expected preparing commit")
  }
  assert_true(preparing.files[0].old_side is Loading)
  assert_false(preparing.files[0].expanded)
  let (running, _) = update(
    retrying,
    SourceLoaded(9, 0, Old, Ok(("text/plain", @utf8.encode("old")))),
    emit,
  )
  assert_true(running.analysis_status is Analyzing)
}

///|
test "analysis HTTP responses preserve friendly backend errors" {
  let backend_message = "OpenSeek left 1 hunk out of the analysis. Please retry."
  let error_body =
    #|{"version":1,"ok":false,"error":{"code":"invalid_coverage","message":"OpenSeek left 1 hunk out of the analysis. Please retry."}}
  guard decode_analysis_http_response(false, 502, "Bad Gateway", error_body)
    is Err(message) else {
    fail("expected backend analysis error")
  }
  assert_eq(message, backend_message)

  guard decode_analysis_http_response(false, 502, "Bad Gateway", "not-json")
    is Err(fallback) else {
    fail("expected fallback analysis error")
  }
  assert_eq(
    fallback, "The analysis request failed (HTTP 502 Bad Gateway). Please retry.",
  )

  let success_body =
    #|{"version":1,"ok":true,"analysis":{"summary":"Summary","groups":[]}}
  guard decode_analysis_http_response(true, 200, "OK", success_body)
    is Ok(response) else {
    fail("expected decoded analysis response")
  }
  assert_eq(response.analysis.summary, "Summary")
}

///|
test "stale analysis responses are discarded by commit generation" {
  let file = fixture_file("README.md", "modified")
  let view = set_file_state(analysis_test_view([file]), 0, {
    file,
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["old"]),
    new_side: Ready(["new"]),
    diff_cache: empty_diff_cache(),
  })
  let model = analysis_test_model(view, status=Analyzing)
  let response = AnalysisResponse::{
    version: ANALYSIS_VERSION,
    ok: true,
    analysis: {
      summary: "Summary",
      groups: [
        {
          title: "Group",
          description: "Description",
          hunks: [{ id: "f0-h0", explanation: "Explanation" }],
        },
      ],
    },
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update(model, AnalysisLoaded(8, Ok(response)), emit)
  assert_true(after == model)
}

///|
test "analysis groups open the most important result first and toggle independently" {
  let file = fixture_file("README.md", "modified")
  let view = set_file_state(analysis_test_view([file]), 0, {
    file,
    diff_mode: LineDiff,
    expanded: false,
    old_side: Ready(["old"]),
    new_side: Ready(["new"]),
    diff_cache: empty_diff_cache(),
  })
  let model = analysis_test_model(view, status=Analyzing)
  let response = AnalysisResponse::{
    version: ANALYSIS_VERSION,
    ok: true,
    analysis: {
      summary: "Summary",
      groups: [
        {
          title: "Important",
          description: "Review first.",
          hunks: [{ id: "f0-h0", explanation: "Important explanation." }],
        },
        {
          title: "Supporting",
          description: "Review later.",
          hunks: [{ id: "f0-h1", explanation: "Supporting explanation." }],
        },
      ],
    },
  }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (loaded, _) = update(model, AnalysisLoaded(9, Ok(response)), emit)
  guard loaded.analysis_status is AnalysisDone(_, _, initially_expanded) else {
    fail("expected completed analysis")
  }
  assert_eq(initially_expanded, [true, false])
  let (opened, _) = update(loaded, ToggleAnalysisGroup(1), emit)
  guard opened.analysis_status is AnalysisDone(_, _, both_expanded) else {
    fail("expected completed analysis")
  }
  assert_eq(both_expanded, [true, true])
  let (collapsed, _) = update(opened, ToggleAnalysisGroup(0), emit)
  guard collapsed.analysis_status is AnalysisDone(_, _, changed) else {
    fail("expected completed analysis")
  }
  assert_eq(changed, [false, true])
  let (out_of_range, _) = update(collapsed, ToggleAnalysisGroup(10), emit)
  assert_true(out_of_range == collapsed)
}

///|
fn ready_test_file(
  file : ApiFile,
  old : Array[String],
  new : Array[String],
  expanded? : Bool = true,
) -> FileState {
  {
    file,
    diff_mode: file_diff_mode(file),
    expanded,
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: empty_diff_cache(),
  }
}

///|
test "Lexical is the default and algorithm selection is not part of routes" {
  let model = initial_model()
  assert_true(model.diff_algorithm is LexicalAlgorithm)
  let reference = CommitRef::{ owner: "owner", repo: "repo", sha: "abcdef1" }
  assert_eq(playground_route(reference), "#/owner/repo/commit/abcdef1")
  assert_false(playground_route(reference).contains("algorithm"))
}

///|
test "algorithm switching fills the second cache and clears analysis state" {
  let file = fixture_file("src/format.mbt", "modified")
  let lexical_file = ensure_file_document(
    ready_test_file(file, ["fn format() { 1 }"], ["fn format() {", "  1", "}"]),
    LexicalAlgorithm,
  )
  assert_true(lexical_file.diff_cache.lexical is Some(_))
  assert_true(lexical_file.diff_cache.ast is None)
  let view = set_file_state(analysis_test_view([file]), 0, lexical_file)
  let response = AnalysisResult::{ summary: "done", groups: [] }
  let statuses : Array[AnalysisStatus] = [
    Analyzing,
    AnalysisFailed("failed"),
    AnalysisDone(response, [], []),
  ]
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for status in statuses {
    let current = analysis_test_model(view, status~)
    let (switched, _) = update(current, SelectDiffAlgorithm(AstAlgorithm), emit)
    assert_true(switched.diff_algorithm is AstAlgorithm)
    assert_true(switched.analysis_status is AnalysisIdle)
    guard switched.phase is Showing(changed_view) else {
      fail("expected commit to remain visible")
    }
    let changed = changed_view.files[0]
    assert_true(changed.diff_cache.lexical is Some(_))
    guard changed.diff_cache.ast is Some(ast) else {
      fail("expected AST cache")
    }
    assert_true(
      ast.outcome is @alignment.AlignedDiffOutcome::NoStructuralChanges,
    )
  }
}

///|
test "late analysis response is discarded after an algorithm switch" {
  let file = fixture_file("src/change.mbt", "modified")
  let view = set_file_state(
    analysis_test_view([file]),
    0,
    ensure_file_document(
      ready_test_file(file, ["fn f() { old() }"], ["fn f() { new() }"]),
      LexicalAlgorithm,
    ),
  )
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (switched, _) = update(
    analysis_test_model(view, status=Analyzing),
    SelectDiffAlgorithm(AstAlgorithm),
    emit,
  )
  let response = AnalysisResponse::{
    version: ANALYSIS_VERSION,
    ok: true,
    analysis: { summary: "late", groups: [] },
  }
  let (after, _) = update(
    switched,
    AnalysisLoaded(switched.generation, Ok(response)),
    emit,
  )
  assert_true(after == switched)
}

///|
test "new source invalidates both MoonBit algorithm caches" {
  let file = fixture_file("src/change.mbt", "modified")
  let cached = ensure_file_document(
    ensure_file_document(
      ready_test_file(file, ["fn f() { old() }"], ["fn f() { new() }"]),
      LexicalAlgorithm,
    ),
    AstAlgorithm,
  )
  assert_true(cached.diff_cache.lexical is Some(_))
  assert_true(cached.diff_cache.ast is Some(_))
  let view = set_file_state(analysis_test_view([file]), 0, cached)
  let model = { ..analysis_test_model(view), diff_algorithm: AstAlgorithm }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (updated, _) = update(
    model,
    SourceLoaded(
      model.generation,
      0,
      New,
      Ok(("text/plain", @utf8.encode("fn f() { newest() }"))),
    ),
    emit,
  )
  guard updated.phase is Showing(updated_view) else { fail("expected commit") }
  assert_true(updated_view.files[0].diff_cache.lexical is None)
  assert_true(updated_view.files[0].diff_cache.ast is Some(_))
}

///|
test "non-MoonBit line document is shared across algorithm switches" {
  let file = fixture_file("README.md", "modified")
  let cached = ensure_file_document(
    ready_test_file(file, ["old"], ["new"]),
    LexicalAlgorithm,
  )
  guard cached.diff_cache.line is Some(before) else {
    fail("expected line cache")
  }
  let after = ensure_file_document(cached, AstAlgorithm)
  assert_true(after.diff_cache.line == Some(before))
  assert_true(after.diff_cache.lexical is None)
  assert_true(after.diff_cache.ast is None)
}

///|
test "AST structural empty files are skipped without starting backend analysis" {
  let file = fixture_file("src/format.mbt", "modified")
  let state = ready_test_file(file, ["fn format() { 1 }"], [
    "fn format() {", "  1", "}",
  ])
  let view = set_file_state(analysis_test_view([file]), 0, state)
  let model = { ..analysis_test_model(view), diff_algorithm: AstAlgorithm }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  let (after, _) = update(model, AnalyzeChanges, emit)
  guard after.analysis_status is AnalysisNoHunks(skipped) else {
    fail("expected local no-hunks result")
  }
  assert_eq(skipped.map(item => item.path), ["src/format.mbt"])
  assert_true(skipped[0].reason.contains("No structural changes"))
}
