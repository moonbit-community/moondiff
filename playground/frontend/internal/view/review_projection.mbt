///|
// Built once from visible source rows. Rendering only reads these placements.
priv struct ReviewProjection {
  lines : Map[String, String]
  editors : Map[String, String]
}

///|
fn projection_site(
  file : Int,
  old_base : Int,
  new_base : Int,
  item : Int,
  fragment : String,
) -> String {
  "\{file}:\{fragment}:\{old_base}:\{new_base}:\{item}"
}

///|
fn project_document(
  projection : ReviewProjection,
  file : ApiFile,
  index : Int,
  document : @model.HunkDocument,
  mode : ViewMode,
  old_base : Int,
  new_base : Int,
  fragment? : String = "line",
  cache? : FileDerivation,
) -> Unit {
  let mut line_index = 0
  for
    item in review_items(
      cache, file, index, document, old_base, new_base, fragment,
    ) {
    guard item is ReviewLine(row) else { continue }
    let site = projection_site(index, old_base, new_base, line_index, fragment)
    line_index += 1
    for
      (side, line) in [
        (@review.ReviewSide::Left, row.old_line),
        (Right, row.new_line),
      ] {
      if line is Some(line) {
        let key = discussion_key(index, side, line)
        if !projection.lines.contains(key) {
          projection.lines[key] = site
        }
      }
    }
    let anchors = if mode is Unified &&
      (
        row.kind is ContextRow ||
        (row.kind is IgnoredRow && row.old_text == row.new_text)
      ) {
      [row.new_anchor]
    } else {
      [row.old_anchor, row.new_anchor]
    }
    for anchor in anchors {
      if anchor is Some(anchor) {
        let key = discussion_key(index, anchor.side, anchor.line)
        if !projection.editors.contains(key) {
          projection.editors[key] = site
        }
      }
    }
  }
}

///|
fn project_fragment(
  projection : ReviewProjection,
  file : ApiFile,
  index : Int,
  fragment : @mbtdiff.DiffFragment,
  mode : ViewMode,
  old_range : @mbtdiff.LineRange?,
  new_range : @mbtdiff.LineRange?,
  section? : Int,
  cache? : FileDerivation,
) -> Unit {
  project_document(
    projection,
    file,
    index,
    fragment.document,
    mode,
    old_range.map(r => r.start).unwrap_or(0),
    new_range.map(r => r.start).unwrap_or(0),
    fragment=section.map(i => "section:\{i}").unwrap_or("whole"),
    cache?,
  )
}

///|
fn append_file_projection(
  projection : ReviewProjection,
  file : FileState,
  index : Int,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  cache? : FileDerivation,
) -> Unit {
  guard file.expanded && file.old_side is Ready(_) && file.new_side is Ready(_) else {
    return
  }
  guard cached_file_document(file, algorithm, ignore_comments~, ignore_tests~)
    is Some(result) else {
    return
  }
  match result {
    Line(document) =>
      project_document(
        projection,
        file.file,
        index,
        document,
        mode,
        0,
        0,
        cache?,
      )
    MoonBit(document~, status~, ..) if !semantic_document_visible(
        document, status, algorithm,
      ) => ()
    MoonBit(document~, ..) =>
      match document {
        Whole(fragment) =>
          project_fragment(
            projection,
            file.file,
            index,
            fragment,
            mode,
            None,
            None,
            cache?,
          )
        TopLevel(top) => {
          let section_keys = semantic_section_keys(top.sections)
          for deleted in [false, true] {
            for
              section_index in (if deleted {
                top.old_order
              } else {
                top.new_order
              }) {
              guard top.sections.get(section_index) is Some(section) else {
                continue
              }
              if (section is Deleted(..)) != deleted ||
                file.collapsed_sections.contains(section_keys[section_index]) {
                continue
              }
              let fragment = semantic_section_fragment(section)
              if fragment_has_output(fragment) {
                project_fragment(
                  projection,
                  file.file,
                  index,
                  fragment,
                  mode,
                  semantic_section_old_range(section),
                  semantic_section_new_range(section),
                  section=section_index,
                  cache?,
                )
              }
            }
          }
        }
      }
  }
}

///|
fn file_projection(
  file : FileState,
  index : Int,
  mode : ViewMode,
  algorithm : DiffAlgorithm,
  ignore_comments : Bool,
  ignore_tests : Bool,
  cache : FileDerivation,
) -> ReviewProjection {
  if cache.visibility
    is Some((old, old_mode, old_algorithm, old_comments, old_tests)) {
    let same_document = @identity.same_option(
      cached_file_document(
        old,
        old_algorithm,
        ignore_comments=old_comments,
        ignore_tests=old_tests,
      ),
      cached_file_document(file, algorithm, ignore_comments~, ignore_tests~),
    )
    if same_document &&
      @identity.same(old.file, file.file) &&
      old.expanded == file.expanded &&
      @identity.same(old.collapsed_sections, file.collapsed_sections) &&
      mode == old_mode {
      return cache.projection
    }
    if !same_document {
      cache.rows.clear()
    }
  }
  cache.visibility = Some(
    (file, mode, algorithm, ignore_comments, ignore_tests),
  )
  @metrics.count(file.file.filename, "projection")
  let projection : ReviewProjection = { lines: Map([]), editors: Map([]), }
  append_file_projection(
    projection,
    file,
    index,
    mode,
    algorithm,
    ignore_comments,
    ignore_tests,
    cache~,
  )
  cache.projection = projection
  projection
}

///|
fn projected_editor(
  discussions : InlineDiscussions,
  anchor : ReviewAnchor?,
  file_index : Int,
  site : String,
) -> Bool {
  match anchor {
    Some(a) =>
      discussions.projection.editors.get(
        discussion_key(file_index, a.side, a.line),
      ) ==
      Some(site)
    None => false
  }
}

///|
fn semantic_document_visible(
  document : @mbtdiff.DiffDocument,
  status : @model.DiffStatus,
  algorithm : DiffAlgorithm,
) -> Bool {
  !(status is IgnoredOnly) &&
  !(algorithm is AstAlgorithm &&
  status is (Identical | NoStructuralChanges) &&
  !semantic_document_has_fallback(document))
}
