///|
fn is_moonbit_file(path : String) -> Bool {
  path.has_suffix(".mbt") ||
  path.has_suffix(".mbtx") ||
  path == "pkg.generated.mbti" ||
  path.has_suffix("/pkg.generated.mbti") ||
  path == "moon.mod" ||
  path.has_suffix("/moon.mod") ||
  path == "moon.pkg" ||
  path.has_suffix("/moon.pkg")
}

///|
fn source_highlights(
  path : String,
  source : String,
) -> @highlight.SourceHighlights? {
  if is_moonbit_file(path) {
    Some(@highlight_moonbit.highlight(source))
  } else if path.has_suffix(".c") || path.has_suffix(".h") {
    Some(@highlight_c.highlight(source))
  } else {
    None
  }
}

///|
fn file_highlights(
  old_path : String,
  new_path : String,
  old_source : String,
  new_source : String,
) -> @highlight.FileHighlights {
  {
    old: source_highlights(old_path, old_source),
    new: source_highlights(new_path, new_source),
  }
}
