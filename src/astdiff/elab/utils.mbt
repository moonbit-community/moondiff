///|UUID(f70cf036-fb4e-42ac-bada-7bf996d42200)
fn loc_of_type(ty : @syntax.Type) -> @basic.Location {
  match ty {
    Option(loc~, ..) => loc
    Name(loc~, ..) => loc
    Tuple(loc~, ..) => loc
    Arrow(loc~, ..) => loc
    Any(loc~) => loc
    Object(constr_id) => constr_id.loc
  }
}

///|UUID(fbca3974-da89-46a2-b8fe-f42a0db286a8)
fn @basic.Location::sub(self : @basic.Location, width : Int) -> @basic.Location {
  let start = self.start
  let end = { ..start, cnum: start.cnum + width }
  @basic.Location::{ start, end }
}

///|UUID(04ed92c7-34fc-4508-bf9c-e284eebc8296)
fn @basic.Location::rev_sub(
  self : @basic.Location,
  width : Int,
) -> @basic.Location {
  let end = self.end
  let start = { ..end, cnum: end.cnum - width }
  @basic.Location::{ start, end }
}

///|UUID(7799ee00-da1b-4516-bb4a-7a3fbd66d92d)
fn @basic.Position::to_span(self : @basic.Position) -> SingleLineSpan {
  SingleLineSpan::{
    line: self.lnum,
    start_col: self.column(),
    end_col: self.column(),
  }
}

///|UUID(16e23595-14a0-4ba8-83ed-1e802be4b1ba)
fn @basic.Location::start_to_span(self : @basic.Location) -> SingleLineSpan {
  self.start.to_span()
}

///|UUID(7c19d495-072f-4c5c-81d5-83002238be2a)
fn @basic.Location::end_to_span(self : @basic.Location) -> SingleLineSpan {
  self.end.to_span()
}

///|UUID(dd853c7f-2436-4ce5-b293-c647d16c37cc)
fn @syntax.LongIdent::to_str(self : @syntax.LongIdent) -> String {
  match self {
    Ident(name~) => name
    Dot(pkg~, id~) => "@\{pkg}.\{id}"
  }
}

///|UUID(3c5653b2-3801-4d55-8927-5bc94b5666a5)
fn[T] lst_pos_pair(
  lst : @list.List[T],
  loc_of~ : (T) -> @basic.Location,
) -> (SingleLineSpan, SingleLineSpan) {
  if lst is More(head, tail=Empty) {
    let loc = loc_of(head)
    (loc.start.to_span(), loc.end.to_span())
  } else {
    let first_loc = loc_of(lst.head().unwrap())
    let last_loc = loc_of(lst.last().unwrap())
    (first_loc.start.to_span(), last_loc.end.to_span())
  }
}

///|UUID(400d7eac-4a44-4e8c-ad4f-5bbd1bb4a376)
fn[T] lst_search_symmetric(
  line_widths : LineWidths,
  lst : @list.List[T],
  loc_of~ : (T) -> @basic.Location,
  open~ : Char,
  close~ : Char,
) -> (SingleLineSpan, SingleLineSpan) {
  if lst is More(head, tail=Empty) {
    let loc = loc_of(head)
    (
      line_widths.backward_search(open, loc.start),
      line_widths.forward_search(close, loc.end),
    )
  } else {
    let first_loc = loc_of(lst.head().unwrap())
    let last_loc = loc_of(lst.last().unwrap())
    (
      line_widths.backward_search(open, first_loc.start),
      line_widths.forward_search(close, last_loc.end),
    )
  }
}

///|UUID(580f8c7d-a9c8-4cc1-b9a8-39f3175d9243)
fn last_pos_of_fun_decl(fun_decl : @syntax.FunDecl) -> @basic.Position {
  match fun_decl.error_type {
    Noraise(loc~) | DefaultErrorType(loc~) => loc.end
    ErrorType(ty~) | MaybeError(ty~) => loc_of_type(ty).end
    NoErrorType =>
      if fun_decl.return_type is Some(ty) {
        loc_of_type(ty).end
      } else if fun_decl.params_loc.start == fun_decl.params_loc.end {
        // no params
        fun_decl.name.loc.end
      } else {
        fun_decl.params_loc.end
      }
  }
}
