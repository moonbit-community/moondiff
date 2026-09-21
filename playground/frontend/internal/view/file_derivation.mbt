///|
priv struct CachedRows {
  document : @model.HunkDocument
  items : Array[@review.ReviewItem]
}

///|
/// Derived data owned by one mount. No business state or cross-file references.
pub struct FileDerivation {
  priv mut source : ApiFile?
  priv mut patch : @review.CanonicalPatch
  priv rows : Map[String, CachedRows]
  priv mut visibility : (FileState, ViewMode, DiffAlgorithm, Bool, Bool)?
  priv mut projection : ReviewProjection
}

///|
pub fn FileDerivation::new() -> FileDerivation {
  {
    source: None,
    patch: NotCommentable,
    rows: Map([]),
    visibility: None,
    projection: { lines: Map([]), editors: Map([]), },
  }
}

///|
fn canonical_patch(
  cache : FileDerivation?,
  file : ApiFile,
) -> @review.CanonicalPatch {
  if cache is Some(cache) {
    if cache.source is Some(source) && @identity.same(source, file) {
      return cache.patch
    }
    cache.source = Some(file)
    cache.rows.clear()
    @metrics.count(file.filename, "patch")
    cache.patch = parse_canonical_patch(file.filename, file.patch)
    cache.patch
  } else {
    parse_canonical_patch(file.filename, file.patch)
  }
}

///|
fn review_items(
  cache : FileDerivation?,
  file : ApiFile,
  index : Int,
  document : @model.HunkDocument,
  old_base : Int,
  new_base : Int,
  fragment : String,
) -> Array[@review.ReviewItem] {
  let patch = canonical_patch(cache, file)
  let key = "\{fragment}:\{old_base}:\{new_base}"
  if cache is Some(cache) &&
    cache.rows.get(key) is Some(rows) &&
    @identity.same(rows.document, document) {
    return rows.items
  }
  @metrics.count(file.filename, "rows")
  let items = project_review_items(
    index,
    file.filename,
    document,
    patch,
    old_base~,
    new_base~,
  )
  if cache is Some(cache) {
    cache.rows[key] = { document, items, }
  }
  items
}
