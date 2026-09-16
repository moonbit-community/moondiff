///|
fn mbtdiff_mode(algorithm : DiffAlgorithm) -> @mbtdiff.DiffMode {
  match algorithm {
    LexicalAlgorithm => Lexical
    AstAlgorithm => Ast
  }
}

///|
pub fn ignored_change_subject(
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
fn diff_cache_key(
  diff_mode : FileDiffMode,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> CacheKey {
  match diff_mode {
    LineDiff => Line
    MoonBitDiff => MoonBit(algorithm, ignore_comments, ignore_tests)
  }
}

///|
pub fn cached_file_document(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> CachedDiffResult? {
  file.diff_cache.get(
    diff_cache_key(file.diff_mode, algorithm, ignore_comments~, ignore_tests~),
  )
}

///|
pub fn has_navigable_changes(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments~ : Bool,
  ignore_tests~ : Bool,
) -> Bool {
  guard (file.old_side, file.new_side) is (Ready(_), Ready(_)) &&
    cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(MoonBit(document=TopLevel(top), status~, ..)) &&
    !(status is IgnoredOnly) else {
    return false
  }
  top.sections.any(section => {
    let fragment = match section {
      Matched(diff~, ..) | Deleted(diff~, ..) | Inserted(diff~, ..) => diff
    }
    fragment.document.hunks.any(hunk => {
      hunk.blocks.any(block => block is ChangeBlock(rows) && !rows.is_empty())
    })
  })
}

///|
fn calculate_file_document(
  file : FileState,
  key : CacheKey,
) -> CachedDiffResult? {
  guard (file.old_side, file.new_side) is (Ready(old), Ready(new)) else {
    return None
  }
  match key {
    Line => Some(Line(@linediff.line_diff(old~, new~, context=3)))
    MoonBit(algorithm, ignore_comments, ignore_tests) => {
      let result = @mbtdiff.diff(
        old.join("\n"),
        new.join("\n"),
        old_name=file.file.previous_filename.unwrap_or(file.file.filename),
        new_name=file.file.filename,
        options=DiffOptions(
          context_lines=3,
          graph_limit=3_000_000,
          ignore_comments~,
          ignore_tests~,
          mode=mbtdiff_mode(algorithm),
        ),
      )
      Some(
        MoonBit(
          document=result.document(),
          status=result.status(),
          ignore_reason=result.ignore_reason(),
        ),
      )
    }
  }
}

///|
pub fn ensure_file_document(
  file : FileState,
  algorithm : DiffAlgorithm,
  ignore_comments? : Bool = false,
  ignore_tests? : Bool = false,
) -> FileState {
  let file = if file.diff_cache.highlights is None &&
    file.old_side is Ready(old) &&
    file.new_side is Ready(new) {
    {
      ..file,
      diff_cache: {
        ..file.diff_cache,
        highlights: Some(
          file_highlights(
            file.file.previous_filename.unwrap_or(file.file.filename),
            file.file.filename,
            old.join("\n"),
            new.join("\n"),
          ),
        ),
      },
    }
  } else {
    file
  }
  let key = diff_cache_key(
    file.diff_mode,
    algorithm,
    ignore_comments~,
    ignore_tests~,
  )
  if file.diff_cache.get(key) is Some(_) {
    return file
  }
  guard calculate_file_document(file, key) is Some(result) else { return file }
  { ..file, diff_cache: file.diff_cache.put(key, result), }
}

///|
pub fn ensure_expanded_file_documents(
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
    ..view,
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
