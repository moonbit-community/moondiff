///|UUID(7c0c7c9f-4e7b-4ece-9b42-5450f4682b1f)
using @past {
  type AliasTarget,
  type DocString,
  type Impl,
  type Impls,
  type LongIdent,
  type Type,
  type TypeName,
  type UsingKind,
}

///|UUID(e9fe4725-d84d-44b4-9808-9a4e03f95f7d)
using @syntax {type MatchKind, type MatchedPos}

///|UUID(535b5674-e035-46f6-becf-f8cd4ac7ff03)
// One top-level implementation item plus the source range needed to render it
// independently. UUIDs, semantic keys, and unique root hashes let us align
// moved items before running the structural diff.
priv struct ImplUnit {
  root : @syntax.Syntax
  uuid : String?
  semantic_key : String?
  start_line : Int
  end_line : Int
}

///|UUID(53d6d454-50dd-433e-83c9-b2a93eefef14)
// The top-level edit script used when all units carry UUIDs. Replacement means
// "diff these two roots"; delete/insert compare a real root with an empty side.
priv enum ImplEdit {
  Replace(old~ : ImplUnit, new~ : ImplUnit)
  Delete(ImplUnit)
  Insert(ImplUnit)
}

///|UUID(8fd346b7-8ce5-4b06-9148-35ac8601a592)
fn is_uuid_char(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '-'
}

///|UUID(5d752005-29eb-4426-a51b-c7ef06be58b5)
// UUID lines are expected inside doc comments as `UUID(...)`. The parser keeps
// doc comment content without the leading `///|`, so only the payload is parsed
// here.
fn parse_uuid_line(line : String) -> String? {
  let line = line.trim(char_set=" ")
  if !(line.has_prefix("UUID(") && line.has_suffix(")")) {
    return None
  }
  let chars = line.to_array()
  let start = "UUID(".length()
  let end_ = chars.length() - 1
  if start >= end_ {
    return None
  }
  for ch in chars[start:end_] {
    if !is_uuid_char(ch) {
      return None
    }
  }
  Some(String::from_array(chars[start:end_].to_owned()))
}

///|UUID(c8af895b-35ec-44e7-8f9e-f81f90e0bfb9)
fn doc_uuid(doc : DocString) -> String? {
  let uuid = Ref(None)
  doc.content.each(fn(line) {
    if uuid.val is None {
      uuid.val = parse_uuid_line(line)
    }
  })
  uuid.val
}

///|UUID(ff5687d4-4636-433d-ba6c-7ac2ed877abd)
fn doc_has_content(doc : DocString) -> Bool {
  let has_content = Ref(false)
  doc.content.each(fn(_) { has_content.val = true })
  has_content.val
}

///|UUID(7f79051c-265a-4539-bfbd-88bdc902f42e)
fn impl_doc(impl_ : Impl) -> DocString? {
  match impl_ {
    TopExpr(..) => None
    TopTest(doc~, ..)
    | TopLetDef(doc~, ..)
    | TopImpl(doc~, ..)
    | TopView(doc~, ..)
    | TopImplRelation(doc~, ..)
    | TopUsing(doc~, ..) => Some(doc)
    TopTypeDef(decl) => Some(decl.doc)
    TopFuncDef(fun_decl~, ..) => Some(fun_decl.doc)
    TopTrait(decl) => Some(decl.doc)
  }
}

///|UUID(60810475-c784-47f5-9a24-4fcb7c9f8c9f)
fn impl_uuid(impl_ : Impl) -> String? {
  impl_doc(impl_).bind(doc_uuid)
}

///|UUID(6f42fca4-8ba4-4053-848d-151d706f0f1d)
fn long_ident_key(id : LongIdent) -> String {
  match id {
    Ident(name~) => name
    Dot(pkg~, id~, ..) => "\{pkg}.\{id}"
  }
}

///|UUID(0151c50c-bda0-42d2-b04d-83fe7eb3f1ec)
fn type_name_key(name : TypeName) -> String {
  let prefix = if name.is_object { "&" } else { "" }
  prefix + long_ident_key(name.name)
}

///|UUID(f03aa81c-e1a9-4efc-b6db-41dd3441238b)
fn simple_type_key(ty : Type) -> String? {
  match ty {
    Name(constr_id~, tys~, ..) =>
      if tys.is_empty() {
        Some(long_ident_key(constr_id.id))
      } else {
        None
      }
    Object(constr_id~, ..) => Some("&" + long_ident_key(constr_id.id))
    _ => None
  }
}

///|UUID(4987453e-3019-4c32-942c-e723c080bc93)
fn optional_simple_type_key(ty : Type?) -> String? {
  match ty {
    None => Some("")
    Some(ty) => simple_type_key(ty)
  }
}

///|UUID(2588288b-4962-46b8-a9b6-800a78bdf9f4)
fn using_kind_key(kind : UsingKind) -> String {
  match kind {
    Value => "value"
    Type(..) => "type"
    Trait(..) => "trait"
  }
}

///|UUID(b5e5b14f-caa1-4e15-bd2d-f68aa144e294)
fn using_alias_target_key(target : AliasTarget) -> String {
  match target.target {
    Some(actual) => "\{actual.name} as \{target.binder.name}"
    None => target.binder.name
  }
}

///|UUID(c6885b7d-879d-4f86-83c5-93fd1a3988ea)
fn using_names_key(names : @list.List[(AliasTarget, UsingKind)]) -> String {
  let items = Array::new()
  names.each(fn(item) {
    let (target, kind) = item
    items.push("\{using_kind_key(kind)}:\{using_alias_target_key(target)}")
  })
  items.join(",")
}

///|UUID(26abb637-f7b0-49d5-900d-fb2c57b1fded)
fn impl_semantic_key(impl_ : Impl) -> String? {
  match impl_ {
    TopExpr(..) => None
    TopFuncDef(fun_decl~, ..) => {
      let receiver = match fun_decl.type_name {
        Some(type_name) => type_name_key(type_name)
        None => ""
      }
      Some("fn:\{receiver}::\{fun_decl.name.name}")
    }
    TopTypeDef(decl) => Some("type:\{decl.tycon}")
    TopTrait(decl) => Some("trait:\{decl.name.name}")
    TopLetDef(binder~, is_constant~, ..) =>
      if is_constant {
        Some("const:\{binder.name}")
      } else {
        Some("let:\{binder.name}")
      }
    TopTest(name~, ..) =>
      match name {
        Some((name, _)) => Some("test:\{name}")
        None => None
      }
    TopImpl(self_ty~, trait_~, method_name~, ..) =>
      optional_simple_type_key(self_ty).map(fn(self_key) {
        "impl-fn:\{self_key}:\{type_name_key(trait_)}::\{method_name.name}"
      })
    TopImplRelation(self_ty~, trait_~, ..) =>
      simple_type_key(self_ty).map(fn(self_key) {
        "impl:\{self_key}:\{type_name_key(trait_)}"
      })
    TopView(view_type_name~, view_func_name~, ..) =>
      Some("view:\{view_type_name}:\{view_func_name.name}")
    TopUsing(pkg~, names~, ..) =>
      Some("using:\{pkg.name}:\{using_names_key(names)}")
  }
}

///|UUID(3ac7e4c6-c245-48ec-97f9-56e561b4016d)
// Include attached doc comments in the source slice. Otherwise a changed UUID
// or documentation line would be outside the rendered hunk for the declaration.
fn impl_start_line(impl_ : Impl) -> Int {
  let fallback = impl_.loc().start.lnum
  match impl_doc(impl_) {
    Some(doc) =>
      if doc_has_content(doc) {
        doc.loc.start.lnum
      } else {
        fallback
      }
    None => fallback
  }
}

///|UUID(e78433fb-660a-4a48-a7e8-53af2fd22fdc)
fn impl_end_line(impl_ : Impl) -> Int {
  impl_.loc().end.lnum
}

///|UUID(0dbdcb8c-a1be-4a07-bb2f-e9282790f58f)
fn impl_array(impls : Impls) -> Array[Impl] {
  let items = Array::new()
  impls.each(fn(impl_) { items.push(impl_) })
  items
}

///|UUID(7c2c53bf-e829-4e44-bf26-b1c452e3f8a0)
// Elaborate parser items into syntax roots once, while preserving source line
// bounds for later per-item fallback rendering.
fn collect_impl_units(source : String, impls : Impls) -> Array[ImplUnit] {
  let units = Array::new()
  for impl_ in impl_array(impls) {
    units.push(ImplUnit::{
      root: @elab.elab_impl(source, impl_),
      uuid: impl_uuid(impl_),
      semantic_key: impl_semantic_key(impl_),
      start_line: impl_start_line(impl_),
      end_line: impl_end_line(impl_),
    })
  }
  units
}

///|UUID(9ea4541d-91e0-4981-b8f4-c068d6994e52)
fn all_units_have_uuid(units : ArrayView[ImplUnit]) -> Bool {
  units.all(fn(unit) { unit.uuid is Some(_) })
}

///|UUID(75486f71-7af0-4c26-a905-97cdfbc7d623)
// Align duplicated UUIDs by occurrence order. This keeps repeated generated
// declarations deterministic without requiring UUIDs to be globally unique.
fn align_impl_units_by_uuid(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  let new_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([])
  for i in 0..<new_units.length() {
    match new_units[i].uuid {
      Some(uuid) => new_positions.get_or_init(uuid, fn() { [] }).push(i)
      None => panic()
    }
  }

  let new_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let used_new : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let edits = Array::new()

  for old_unit in old_units {
    match old_unit.uuid {
      Some(uuid) =>
        match new_positions.get(uuid) {
          Some(indices) => {
            let offset = new_offsets.get(uuid).unwrap_or(0)
            if offset < indices.length() {
              let new_index = indices[offset]
              new_offsets[uuid] = offset + 1
              used_new.set(new_index, true)
              edits.push(Replace(old=old_unit, new=new_units[new_index]))
            } else {
              edits.push(Delete(old_unit))
            }
          }
          None => edits.push(Delete(old_unit))
        }
      None => panic()
    }
  }

  for i in 0..<new_units.length() {
    if !used_new.contains(i) {
      edits.push(Insert(new_units[i]))
    }
  }
  edits
}

///|UUID(218731b6-e35d-469a-b7a9-a31dcc3b1c70)
fn align_impl_units_by_key(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  let old_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let new_used : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap([])
  let replacements : @hashmap.HashMap[Int, Int] = @hashmap.HashMap([])

  fn pair(old_index : Int, new_index : Int) -> Unit {
    if !old_used.contains(old_index) && !new_used.contains(new_index) {
      old_used.set(old_index, true)
      new_used.set(new_index, true)
      replacements.set(old_index, new_index)
    }
  }

  let new_uuid_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<new_units.length() {
    match new_units[i].uuid {
      Some(uuid) => new_uuid_positions.get_or_init(uuid, fn() { [] }).push(i)
      None => ()
    }
  }
  let uuid_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for i in 0..<old_units.length() {
    match old_units[i].uuid {
      Some(uuid) =>
        match new_uuid_positions.get(uuid) {
          Some(indices) => {
            let offset = uuid_offsets.get(uuid).unwrap_or(0)
            if offset < indices.length() {
              uuid_offsets[uuid] = offset + 1
              pair(i, indices[offset])
            }
          }
          None => ()
        }
      None => ()
    }
  }

  let new_key_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<new_units.length() {
    if !new_used.contains(i) {
      match new_units[i].semantic_key {
        Some(key) => new_key_positions.get_or_init(key, fn() { [] }).push(i)
        None => ()
      }
    }
  }
  let key_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      match old_units[i].semantic_key {
        Some(key) =>
          match new_key_positions.get(key) {
            Some(indices) => {
              let offset = key_offsets.get(key).unwrap_or(0)
              if offset < indices.length() {
                key_offsets[key] = offset + 1
                pair(i, indices[offset])
              }
            }
            None => ()
          }
        None => ()
      }
    }
  }

  let old_roots = impl_roots(old_units)
  let new_roots = impl_roots(new_units)
  @syntax.init_all_info(old_roots, new_roots)
  let old_content_counts : @hashmap.HashMap[UInt, Int] = @hashmap.HashMap([])
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      let content_id = old_units[i].root.content_id()
      old_content_counts[content_id] = old_content_counts
        .get(content_id)
        .unwrap_or(0) +
        1
    }
  }
  let new_content_positions : @hashmap.HashMap[UInt, Array[Int]] = @hashmap.HashMap([],
  )
  for i in 0..<new_units.length() {
    if !new_used.contains(i) {
      let content_id = new_units[i].root.content_id()
      new_content_positions.get_or_init(content_id, fn() { [] }).push(i)
    }
  }
  for i in 0..<old_units.length() {
    if !old_used.contains(i) {
      let content_id = old_units[i].root.content_id()
      if old_content_counts.get(content_id).unwrap_or(0) == 1 {
        match new_content_positions.get(content_id) {
          Some(indices) => if indices.length() == 1 { pair(i, indices[0]) }
          None => ()
        }
      }
    }
  }

  let edits = Array::new()
  for i in 0..<old_units.length() {
    match replacements.get(i) {
      Some(new_index) =>
        edits.push(Replace(old=old_units[i], new=new_units[new_index]))
      None => edits.push(Delete(old_units[i]))
    }
  }

  for i in 0..<new_units.length() {
    if !new_used.contains(i) {
      edits.push(Insert(new_units[i]))
    }
  }
  edits
}

///|UUID(efd8452b-7521-4f76-9171-86843cf72de6)
fn format_impl_label(label : String, unit : ImplUnit?) -> String {
  match unit {
    Some(unit) => "\{label}: line \{unit.start_line}"
    None => label
  }
}

///|UUID(d1d2c663-315a-4d00-8815-7ff7d1244b40)
fn impl_line_base(unit : ImplUnit?) -> Int {
  match unit {
    Some(unit) => unit.start_line
    None => 1
  }
}

///|UUID(92c64499-ea3f-4acd-8121-453b75789ee2)
// Extract the exact source text for one implementation unit. The caller passes
// the corresponding line base so hunk headers still refer to original file
// lines.
fn source_slice(source : String, unit : ImplUnit?) -> String {
  match unit {
    None => ""
    Some(unit) => {
      let lines = @render.split_lines(source)
      if lines.is_empty() {
        return ""
      }
      let start = @cmp.maximum(unit.start_line - 1, 0)
      let end_ = @cmp.minimum(unit.end_line, lines.length())
      if start >= end_ {
        return ""
      }
      let buf = StringBuilder::new()
      for i in start..<end_ {
        if i > start {
          buf.write_char('\n')
        }
        buf.write_string(lines[i])
      }
      buf.to_string()
    }
  }
}

///|UUID(4d521cbe-fba0-481f-a4c4-bb73a4787f81)
fn rebase_span(
  span : @span.SingleLineSpan,
  delta : Int,
) -> @span.SingleLineSpan {
  @span.SingleLineSpan::{
    line: span.line - delta,
    start_col: span.start_col,
    end_col: span.end_col,
  }
}

///|UUID(34c71798-ef33-4462-bbc6-a6d7965ade32)
// Per-unit diffs run on sliced source text. Rebase structural positions so the
// renderer can operate on the slice while hunk labels keep the original line
// numbers.
fn rebase_matched_positions(
  positions : ArrayView[MatchedPos],
  own_delta : Int,
  opposite_delta : Int,
) -> Array[MatchedPos] {
  let rebased = Array::new()
  for position in positions {
    let kind = match position.kind {
      Novel => MatchKind::Novel
      Unchanged(opposite_pos~) =>
        MatchKind::Unchanged(
          opposite_pos=opposite_pos.map(fn(span) {
            rebase_span(span, opposite_delta)
          }),
        )
    }
    rebased.push(MatchedPos::{ kind, pos: rebase_span(position.pos, own_delta) })
  }
  rebased
}

///|UUID(2d9e21e9-c8cc-40cf-b572-5e163bf3b4b8)
// If the tree graph grows beyond the configured limit for a single unit, show a
// regular line diff for just that unit instead of abandoning the whole file.
fn render_impl_line_fallback(
  reason : String,
  old_label : String,
  old_source : String,
  old_unit : ImplUnit?,
  new_label : String,
  new_source : String,
  new_unit : ImplUnit?,
  render_options : @render.RenderOptions,
) -> String {
  let old_slice = source_slice(old_source, old_unit)
  let new_slice = source_slice(new_source, new_unit)
  let old_line_base = impl_line_base(old_unit)
  let new_line_base = impl_line_base(new_unit)
  "note: fallback to line diff (\{reason})\n" +
  @render.render_line_diff(
    format_impl_label(old_label, old_unit),
    old_slice,
    format_impl_label(new_label, new_unit),
    new_slice,
    None,
    None,
    render_options,
    old_line_base~,
    new_line_base~,
  )
}

///|UUID(b38a16e3-c759-41aa-93fc-db2763cc9bcb)
// Render one top-level edit. Empty-side edits are represented by omitting the
// corresponding root, which lets the normal structural path mark the whole unit
// as novel when the graph stays within limits.
fn render_impl_edit(
  old_label : String,
  old_source : String,
  old_unit : ImplUnit?,
  new_label : String,
  new_source : String,
  new_unit : ImplUnit?,
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String? {
  let old_slice = source_slice(old_source, old_unit)
  let new_slice = source_slice(new_source, new_unit)
  let old_line_base = impl_line_base(old_unit)
  let new_line_base = impl_line_base(new_unit)
  let lhs_roots = Array::new()
  let rhs_roots = Array::new()
  match old_unit {
    Some(unit) => lhs_roots.push(unit.root)
    None => ()
  }
  match new_unit {
    Some(unit) => rhs_roots.push(unit.root)
    None => ()
  }

  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, graph_limit) catch {
    _ =>
      return Some(
        render_impl_line_fallback(
          "graph limit exceeded (\{graph_limit})",
          old_label,
          old_source,
          old_unit,
          new_label,
          new_source,
          new_unit,
          render_options,
        ),
      )
  }

  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)

  let lhs_positions = rebase_matched_positions(
    @syntax.change_positions(lhs_roots, change_map),
    old_line_base - 1,
    new_line_base - 1,
  )
  let rhs_positions = rebase_matched_positions(
    @syntax.change_positions(rhs_roots, change_map),
    new_line_base - 1,
    old_line_base - 1,
  )
  if @hunks.matched_pos_to_hunks(lhs_positions, rhs_positions).is_empty() {
    None
  } else {
    Some(
      @render.render_ast_diff(
        format_impl_label(old_label, old_unit),
        old_slice,
        format_impl_label(new_label, new_unit),
        new_slice,
        lhs_positions,
        rhs_positions,
        render_options,
        old_line_base~,
        new_line_base~,
      ),
    )
  }
}

///|UUID(a20b165d-89ae-42ea-a43a-2c4ff53fd6ca)
fn render_no_changes(
  old_label : String,
  new_label : String,
  render_options : @render.RenderOptions,
) -> String {
  @render.render_file_headers(old_label, new_label, render_options.use_color) +
  "No changes.\n"
}

///|UUID(58ac384d-5e05-4e16-8ced-e465cedf4774)
fn impl_roots(units : ArrayView[ImplUnit]) -> Array[@syntax.Syntax] {
  let roots = Array::new()
  for unit in units {
    roots.push(unit.root)
  }
  roots
}

///|UUID(86aa7e88-7f7a-4232-baf0-b765d970f8f2)
fn render_root_list_line_fallback(
  reason : String,
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  render_options : @render.RenderOptions,
) -> String {
  "note: fallback to line diff (\{reason})\n" +
  @render.render_line_diff(
    old_label,
    old_source,
    new_label,
    new_source,
    None,
    None,
    render_options,
  )
}

///|UUID(97bfcfe4-80de-498e-a147-90d250e6c93e)
fn impl_edits_have_replacement(edits : ArrayView[ImplEdit]) -> Bool {
  edits.any(fn(edit) {
    match edit {
      Replace(..) => true
      _ => false
    }
  })
}

///|UUID(85a087f2-92d2-4240-8b75-a5c086d18e14)
fn render_impl_edits(
  old_label : String,
  old_source : String,
  new_label : String,
  new_source : String,
  edits : ArrayView[ImplEdit],
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String {
  let buf = StringBuilder::new()
  let mut wrote = false
  for edit in edits {
    let rendered = match edit {
      Replace(old~, new~) =>
        render_impl_edit(
          old_label,
          old_source,
          Some(old),
          new_label,
          new_source,
          Some(new),
          graph_limit,
          render_options,
        )
      Delete(old) =>
        render_impl_edit(
          old_label,
          old_source,
          Some(old),
          new_label,
          new_source,
          None,
          graph_limit,
          render_options,
        )
      Insert(new) =>
        render_impl_edit(
          old_label,
          old_source,
          None,
          new_label,
          new_source,
          Some(new),
          graph_limit,
          render_options,
        )
    }
    match rendered {
      Some(rendered) => {
        if wrote {
          buf.write_char('\n')
        }
        buf.write_string(rendered)
        wrote = true
      }
      None => ()
    }
  }
  if wrote {
    buf.to_string()
  } else {
    render_no_changes(old_label, new_label, render_options)
  }
}

///|UUID(5904eab2-e4fe-4ce5-b9bc-b437e4d7191f)
// UUID alignment diffs top-level units independently. This makes moved or
// reordered declarations easier to read and limits graph size per comparison.
fn render_uuid_aligned_impl_diffs(
  old_label : String,
  old_source : String,
  old_units : ArrayView[ImplUnit],
  new_label : String,
  new_source : String,
  new_units : ArrayView[ImplUnit],
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String {
  render_impl_edits(
    old_label,
    old_source,
    new_label,
    new_source,
    align_impl_units_by_uuid(old_units, new_units),
    graph_limit,
    render_options,
  )
}

///|UUID(8d173f23-17f9-43af-a67e-f7a7592399e5)
fn render_key_aligned_impl_diffs(
  old_label : String,
  old_source : String,
  old_units : ArrayView[ImplUnit],
  new_label : String,
  new_source : String,
  new_units : ArrayView[ImplUnit],
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String? {
  let edits = align_impl_units_by_key(old_units, new_units)
  if !impl_edits_have_replacement(edits) {
    return None
  }
  Some(
    render_impl_edits(
      old_label, old_source, new_label, new_source, edits, graph_limit, render_options,
    ),
  )
}

///|UUID(109a4d3f-cbaa-42e9-a5d5-5680327e8e55)
// When UUIDs are missing, fall back to a single root-list diff, matching the
// regular difftastic strategy of comparing syntax roots in order.
fn render_root_list_diff(
  old_label : String,
  old_source : String,
  old_units : ArrayView[ImplUnit],
  new_label : String,
  new_source : String,
  new_units : ArrayView[ImplUnit],
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String {
  let lhs_roots = impl_roots(old_units)
  let rhs_roots = impl_roots(new_units)
  @syntax.init_all_info(lhs_roots, rhs_roots)
  let change_map = @syntax.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, graph_limit) catch {
    _ =>
      return render_root_list_line_fallback(
        "graph limit exceeded (\{graph_limit})",
        old_label,
        old_source,
        new_label,
        new_source,
        render_options,
      )
  }

  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)

  @render.render_ast_diff(
    old_label,
    old_source,
    new_label,
    new_source,
    @syntax.change_positions(lhs_roots, change_map),
    @syntax.change_positions(rhs_roots, change_map),
    render_options,
  )
}

///|UUID(efd2e0c6-d9fc-4b57-b551-e31b0146cde7)
// Fully annotated files keep the UUID-only path. Otherwise use conservative
// semantic/hash alignment when at least one top-level pair is reliable, and
// retain the whole root-list diff when no reliable pair exists.
pub fn render_aligned_impl_diffs(
  old_label : String,
  old_source : String,
  old_impls : Impls,
  new_label : String,
  new_source : String,
  new_impls : Impls,
  graph_limit : UInt,
  render_options : @render.RenderOptions,
) -> String {
  let old_units = collect_impl_units(old_source, old_impls)
  let new_units = collect_impl_units(new_source, new_impls)
  if all_units_have_uuid(old_units) && all_units_have_uuid(new_units) {
    render_uuid_aligned_impl_diffs(
      old_label, old_source, old_units, new_label, new_source, new_units, graph_limit,
      render_options,
    )
  } else {
    match
      render_key_aligned_impl_diffs(
        old_label, old_source, old_units, new_label, new_source, new_units, graph_limit,
        render_options,
      ) {
      Some(rendered) => rendered
      None =>
        render_root_list_diff(
          old_label, old_source, old_units, new_label, new_source, new_units, graph_limit,
          render_options,
        )
    }
  }
}
