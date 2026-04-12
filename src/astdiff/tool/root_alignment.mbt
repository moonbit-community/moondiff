///|UUID(7c0c7c9f-4e7b-4ece-9b42-5450f4682b1f)
using @past {type DocString, type Impl, type Impls}

///|UUID(535b5674-e035-46f6-becf-f8cd4ac7ff03)
priv struct ImplUnit {
  root : @syntax.Syntax
  uuid : String?
  start_line : Int
  end_line : Int
}

///|UUID(53d6d454-50dd-433e-83c9-b2a93eefef14)
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
  Some(String::from_array(chars[start:end_].to_array()))
}

///|UUID(c8af895b-35ec-44e7-8f9e-f81f90e0bfb9)
fn doc_uuid(doc : DocString) -> String? {
  let uuid = Ref::new(None)
  doc.content.each(fn(line) {
    if uuid.val is None {
      uuid.val = parse_uuid_line(line)
    }
  })
  uuid.val
}

///|UUID(ff5687d4-4636-433d-ba6c-7ac2ed877abd)
fn doc_has_content(doc : DocString) -> Bool {
  let has_content = Ref::new(false)
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
    TopTypeDef(decl, ..) => Some(decl.doc)
    TopFuncDef(fun_decl~, ..) => Some(fun_decl.doc)
    TopTrait(decl, ..) => Some(decl.doc)
  }
}

///|UUID(60810475-c784-47f5-9a24-4fcb7c9f8c9f)
fn impl_uuid(impl_ : Impl) -> String? {
  impl_doc(impl_).bind(doc_uuid)
}

///|UUID(3ac7e4c6-c245-48ec-97f9-56e561b4016d)
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
fn collect_impl_units(source : String, impls : Impls) -> Array[ImplUnit] {
  let units = Array::new()
  for impl_ in impl_array(impls) {
    units.push(ImplUnit::{
      root: @elab.elab_impl(source, impl_),
      uuid: impl_uuid(impl_),
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

///|UUID(58ac384d-5e05-4e16-8ced-e465cedf4774)
fn align_impl_units_by_order(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  let edits = Array::new()
  let shared = @cmp.minimum(old_units.length(), new_units.length())
  for i in 0..<shared {
    edits.push(Replace(old=old_units[i], new=new_units[i]))
  }
  for i in shared..<old_units.length() {
    edits.push(Delete(old_units[i]))
  }
  for i in shared..<new_units.length() {
    edits.push(Insert(new_units[i]))
  }
  edits
}

///|UUID(75486f71-7af0-4c26-a905-97cdfbc7d623)
fn align_impl_units_by_uuid(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  let new_positions : @hashmap.HashMap[String, Array[Int]] = @hashmap.HashMap::new()
  for i in 0..<new_units.length() {
    match new_units[i].uuid {
      Some(uuid) => new_positions.get_or_init(uuid, fn() { [] }).push(i)
      None => panic()
    }
  }

  let new_offsets : @hashmap.HashMap[String, Int] = @hashmap.HashMap::new()
  let used_new : @hashmap.HashMap[Int, Bool] = @hashmap.HashMap::new()
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

///|UUID(86aa7e88-7f7a-4232-baf0-b765d970f8f2)
fn align_impl_units(
  old_units : ArrayView[ImplUnit],
  new_units : ArrayView[ImplUnit],
) -> Array[ImplEdit] {
  if all_units_have_uuid(old_units) && all_units_have_uuid(new_units) {
    align_impl_units_by_uuid(old_units, new_units)
  } else {
    align_impl_units_by_order(old_units, new_units)
  }
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
fn source_slice(source : String, unit : ImplUnit?) -> String {
  match unit {
    None => ""
    Some(unit) => {
      let lines = split_lines(source)
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
fn rebase_matched_positions(
  positions : ArrayView[MatchedPos],
  own_delta : Int,
  opposite_delta : Int,
) -> Array[MatchedPos] {
  let rebased = Array::new()
  for position in positions {
    let kind = match position.kind {
      Novel => Novel
      Unchanged(opposite_pos~) =>
        Unchanged(
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
fn render_impl_line_fallback(
  reason : String,
  old_label : String,
  old_source : String,
  old_unit : ImplUnit?,
  new_label : String,
  new_source : String,
  new_unit : ImplUnit?,
  options : DiffOptions,
) -> String {
  let old_slice = source_slice(old_source, old_unit)
  let new_slice = source_slice(new_source, new_unit)
  let old_line_base = impl_line_base(old_unit)
  let new_line_base = impl_line_base(new_unit)
  "note: fallback to line diff (\{reason})\n" +
  render_line_diff(
    format_impl_label(old_label, old_unit),
    old_slice,
    format_impl_label(new_label, new_unit),
    new_slice,
    None,
    None,
    options,
    old_line_base~,
    new_line_base~,
  )
}

///|UUID(b38a16e3-c759-41aa-93fc-db2763cc9bcb)
fn render_impl_edit(
  old_label : String,
  old_source : String,
  old_unit : ImplUnit?,
  new_label : String,
  new_source : String,
  new_unit : ImplUnit?,
  options : DiffOptions,
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
  let change_map = @diff.ChangeMap::new()
  @diff.mark_syntax_roots(lhs_roots, rhs_roots, change_map, options.graph_limit) catch {
    _ =>
      return Some(
        render_impl_line_fallback(
          "graph limit exceeded (\{options.graph_limit})",
          old_label,
          old_source,
          old_unit,
          new_label,
          new_source,
          new_unit,
          options,
        ),
      )
  }

  @diff.fix_all_sliders(lhs_roots, change_map)
  @diff.fix_all_sliders(rhs_roots, change_map)

  let lhs_positions = rebase_matched_positions(
    change_positions(lhs_roots, change_map),
    old_line_base - 1,
    new_line_base - 1,
  )
  let rhs_positions = rebase_matched_positions(
    change_positions(rhs_roots, change_map),
    new_line_base - 1,
    old_line_base - 1,
  )
  if matched_pos_to_hunks(lhs_positions, rhs_positions).is_empty() {
    None
  } else {
    Some(
      render_ast_diff(
        format_impl_label(old_label, old_unit),
        old_slice,
        format_impl_label(new_label, new_unit),
        new_slice,
        lhs_positions,
        rhs_positions,
        options,
        old_line_base~,
        new_line_base~,
      ),
    )
  }
}

///|UUID(a20b165d-89ae-42ea-a43a-2c4ff53fd6ca)
fn render_no_changes(old_label : String, new_label : String) -> String {
  "--- \{old_label}\n" + "+++ \{new_label}\n" + "No changes.\n"
}

///|UUID(5904eab2-e4fe-4ce5-b9bc-b437e4d7191f)
fn render_aligned_impl_diffs(
  old_label : String,
  old_source : String,
  old_impls : Impls,
  new_label : String,
  new_source : String,
  new_impls : Impls,
  options : DiffOptions,
) -> String {
  let old_units = collect_impl_units(old_source, old_impls)
  let new_units = collect_impl_units(new_source, new_impls)
  let edits = align_impl_units(old_units, new_units)

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
          options,
        )
      Delete(old) =>
        render_impl_edit(
          old_label,
          old_source,
          Some(old),
          new_label,
          new_source,
          None,
          options,
        )
      Insert(new) =>
        render_impl_edit(
          old_label,
          old_source,
          None,
          new_label,
          new_source,
          Some(new),
          options,
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
    render_no_changes(old_label, new_label)
  }
}
