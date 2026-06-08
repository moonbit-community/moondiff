pub fn AstManager::mk_distinct(
  self : AstManager,
  args : Array[@util.ExprId],
) -> Result[@util.ExprId, @util.Diagnostic] {
  if args.length() <= 1 {
    Ok(self.intern(Distinct(args.copy()), self.bool_sort()))
  } else {
    let sort = self.expr_sort(args[0])
    for arg in args {
      if self.expr_sort(arg) != sort {
        return Err(
          @util.type_error("distinct arguments have different sorts", None),
        )
      }
    }
    Ok(self.intern(Distinct(args.copy()), self.bool_sort()))
  }
}