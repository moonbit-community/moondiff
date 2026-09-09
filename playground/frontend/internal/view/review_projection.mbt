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
) -> Unit {
  let patch = parse_canonical_patch(file.filename, file.patch)
  let mut line_index = 0
  for
    item in project_review_items(
      index,
      file.filename,
      document,
      patch,
      old_base~,
      new_base~,
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
  )
}

///|
fn review_projection(view : ChangeView, model : Model) -> ReviewProjection {
  let projection = ReviewProjection::{ lines: Map([]), editors: Map([]), }
  for index, file in view.files {
    guard file.expanded &&
      file.old_side is Ready(_) &&
      file.new_side is Ready(_) else {
      continue
    }
    guard cached_file_document(
        file,
        model.diff_algorithm,
        ignore_comments=model.ignore_comments,
        ignore_tests=model.ignore_tests,
      )
      is Some(result) else {
      continue
    }
    match result {
      Line(document) =>
        project_document(
          projection,
          file.file,
          index,
          document,
          model.view_mode,
          0,
          0,
        )
      MoonBit(document~, status~, ..) if !semantic_document_visible(
          document,
          status,
          model.diff_algorithm,
        ) => ()
      MoonBit(document~, ..) =>
        match document {
          Whole(fragment) =>
            project_fragment(
              projection,
              file.file,
              index,
              fragment,
              model.view_mode,
              None,
              None,
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
                    model.view_mode,
                    semantic_section_old_range(section),
                    semantic_section_new_range(section),
                    section=section_index,
                  )
                }
              }
            }
          }
        }
    }
  }
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
