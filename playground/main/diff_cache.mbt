///|
fn mbtdiff_mode(algorithm : DiffAlgorithm) -> @mbtdiff.DiffMode {
  match algorithm {
    LexicalAlgorithm => @mbtdiff.DiffMode::Lexical
    AstAlgorithm => @mbtdiff.DiffMode::Ast
  }
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
    LineDiff => Some(Line(@linediff.line_diff(old~, new~, context=3)))
    MoonBitDiff => {
      let result = @mbtdiff.diff(
        old.join("\n"),
        new.join("\n"),
        options=@mbtdiff.DiffOptions(
          graph_limit=3_000_000,
          ignore_comments~,
          ignore_tests~,
          mode=mbtdiff_mode(algorithm),
        ),
      )
      Some(MoonBit(document=result.document(), status=result.status()))
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
