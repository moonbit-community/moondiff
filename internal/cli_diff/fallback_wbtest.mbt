///|
test "syntax-position fallback text distinguishes whole files and regions" {
  assert_eq(
    fallback_reason_text({
      reason: SyntaxPositionsOutOfBounds(sides=[Old, New]),
      scope: WholeFile,
    }),
    "syntax positions out of bounds on the old and new sides",
  )
  assert_eq(
    fallback_reason_text({
      reason: SyntaxPositionsOutOfBounds(sides=[New]),
      scope: Region(
        old=Some({ start: 1, len: 2 }),
        new=Some({ start: 3, len: 2 }),
      ),
    }),
    "syntax positions out of bounds on the new side at old line 2, new line 4",
  )
}
