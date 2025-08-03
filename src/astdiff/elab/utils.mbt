///|
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

///|
fn @basic.Location::sub(self : @basic.Location, width : Int) -> @basic.Location {
  let start = self.start
  let end = { ..start, cnum: start.cnum + width }
  @basic.Location::{ start, end }
}

///|
fn @basic.Location::rev_sub(
  self : @basic.Location,
  width : Int,
) -> @basic.Location {
  let end = self.end
  let start = { ..end, cnum: end.cnum - width }
  @basic.Location::{ start, end }
}

///|
fn @basic.Position::to_span(self : @basic.Position) -> SingleLineSpan {
  SingleLineSpan::{
    line: self.lnum,
    start_col: self.column(),
    end_col: self.column(),
  }
}

///|
fn @basic.Location::start_to_span(self : @basic.Location) -> SingleLineSpan {
  self.start.to_span()
}

///|
fn @basic.Location::end_to_span(self : @basic.Location) -> SingleLineSpan {
  self.end.to_span()
}

///|
fn @syntax.LongIdent::to_str(self : @syntax.LongIdent) -> String {
  match self {
    Ident(name~) => name
    Dot(pkg~, id~) => "@\{pkg}.\{id}"
  }
}

///|
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

///|
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

///|
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
