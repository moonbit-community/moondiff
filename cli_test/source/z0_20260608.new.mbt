pub fn AstManager::mk_distinct(
  self : AstManager,
  args : Array[@util.ExprId],
) -> @util.ExprId raise @type_error.TypeError {
  if args.length() <= 1 {
    self.intern(Distinct(args.copy()), self.bool_sort())
  } else {
    let sort = self.expr_sort(args[0])
    for arg in args {
      if self.expr_sort(arg) != sort {
        raise @type_error.TypeError(
          "distinct arguments have different sorts",
          None,
        )
      }
    }
    self.intern(Distinct(args.copy()), self.bool_sort())
  }
}